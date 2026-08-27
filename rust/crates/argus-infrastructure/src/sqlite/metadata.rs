//! Transaction-bound metadata enrichment persistence.

use argus_application::{
    ExternalIdentityMapping, MappingState, MatchBasis, MetadataProviderSettings,
    MetadataRepository, MetadataSettings, PersistenceError, ProviderId, ProviderMetadata,
    ResolvedMetadata,
};
use argus_domain::GameContentId;
use rusqlite::{OptionalExtension, params};

use super::errors::operation_error;
use super::logical::{
    refresh_game_library_projection, refresh_games_for_content, refresh_games_for_provider_metadata,
};
use super::unit_of_work::SqliteUnitOfWork;

/// Ephemeral metadata repository view over one active SQLite transaction.
pub struct SqliteMetadataRepository<'scope, 'connection> {
    work: &'scope mut SqliteUnitOfWork<'connection>,
}

impl<'scope, 'connection> SqliteMetadataRepository<'scope, 'connection> {
    /// Creates a repository bound to the active transaction.
    pub(crate) fn new(work: &'scope mut SqliteUnitOfWork<'connection>) -> Self {
        Self { work }
    }
}

impl MetadataRepository for SqliteMetadataRepository<'_, '_> {
    fn save_mapping(&mut self, mapping: &ExternalIdentityMapping) -> Result<(), PersistenceError> {
        let content_id = mapping.game_content_id().to_string();
        self.work
            .transaction_mut()?
            .execute(
                "INSERT INTO external_identity_mapping
                    (mapping_id, game_content_id, provider_id, external_game_id,
                     external_release_id, provider_platform_id, provider_confidence,
                     match_basis, provider_revision, state, matched_at, last_validated_at)
                 VALUES
                    (lower(hex(randomblob(16))), ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
                 ON CONFLICT(game_content_id, provider_id, external_game_id, external_release_id)
                 DO UPDATE SET provider_platform_id = excluded.provider_platform_id,
                               provider_confidence = excluded.provider_confidence,
                               match_basis = excluded.match_basis,
                               provider_revision = excluded.provider_revision,
                               state = excluded.state,
                               matched_at = excluded.matched_at,
                               last_validated_at = excluded.last_validated_at",
                params![
                    mapping.game_content_id().to_string(),
                    mapping.provider_id().as_str(),
                    mapping.external_game_id(),
                    mapping.external_release_id(),
                    mapping.provider_platform_id(),
                    mapping.provider_confidence().map(f64::from),
                    mapping.match_basis().as_str(),
                    i64::try_from(mapping.provider_revision()).unwrap_or(i64::MAX),
                    mapping.state().as_str(),
                    mapping.matched_at().to_string(),
                    mapping.last_validated_at().to_string(),
                ],
            )
            .map_err(map_persistence_error)?;
        refresh_games_for_content(self.work.transaction_mut()?, &content_id)?;
        Ok(())
    }

    fn save_provider_metadata(
        &mut self,
        metadata: &ProviderMetadata,
    ) -> Result<(), PersistenceError> {
        self.work
            .transaction_mut()?
            .execute(
                "INSERT INTO provider_metadata
                    (provider_metadata_id, provider_id, external_game_id, provider_revision,
                     region, language, fetched_at, expires_at, title, alternate_titles,
                     description, release_date, developers, publishers, genres, languages,
                     adapter_quality, provenance)
                 VALUES
                    (lower(hex(randomblob(16))), ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9,
                     ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17)
                 ON CONFLICT(provider_id, external_game_id, provider_revision, region, language)
                 DO UPDATE SET fetched_at = excluded.fetched_at,
                               expires_at = excluded.expires_at,
                               title = excluded.title,
                               alternate_titles = excluded.alternate_titles,
                               description = excluded.description,
                               release_date = excluded.release_date,
                               developers = excluded.developers,
                               publishers = excluded.publishers,
                               genres = excluded.genres,
                               languages = excluded.languages,
                               adapter_quality = excluded.adapter_quality,
                               provenance = excluded.provenance",
                params![
                    metadata.provider_id().as_str(),
                    metadata.external_game_id(),
                    i64::try_from(metadata.provider_revision()).unwrap_or(i64::MAX),
                    metadata.region(),
                    metadata.language(),
                    metadata.fetched_at().to_string(),
                    metadata.expires_at().map(|value| value.to_string()),
                    metadata.title(),
                    join_values(metadata.alternate_titles()),
                    metadata.description(),
                    metadata.release_date(),
                    join_values(metadata.developers()),
                    join_values(metadata.publishers()),
                    join_values(metadata.genres()),
                    join_values(metadata.languages()),
                    i64::from(metadata.adapter_quality()),
                    metadata.provenance(),
                ],
            )
            .map_err(map_persistence_error)?;
        refresh_games_for_provider_metadata(
            self.work.transaction_mut()?,
            metadata.provider_id().as_str(),
            metadata.external_game_id(),
            metadata.provider_revision(),
        )?;
        Ok(())
    }

    fn save_resolved_metadata(
        &mut self,
        game_id: argus_domain::GameId,
        metadata: &ResolvedMetadata,
    ) -> Result<(), PersistenceError> {
        self.work
            .transaction_mut()?
            .execute(
                "INSERT INTO resolved_metadata
                    (game_id, display_title, sort_title, description, release_date,
                     developers, publishers, genres, languages, presentation_region,
                     field_provenance, resolution_revision, resolved_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)
                 ON CONFLICT(game_id) DO UPDATE SET
                    display_title = excluded.display_title,
                    sort_title = excluded.sort_title,
                    description = excluded.description,
                    release_date = excluded.release_date,
                    developers = excluded.developers,
                    publishers = excluded.publishers,
                    genres = excluded.genres,
                    languages = excluded.languages,
                    presentation_region = excluded.presentation_region,
                    field_provenance = excluded.field_provenance,
                    resolution_revision = excluded.resolution_revision,
                    resolved_at = excluded.resolved_at",
                params![
                    game_id.to_string(),
                    metadata.display_title(),
                    metadata.sort_title(),
                    metadata.description(),
                    metadata.release_date(),
                    join_values(metadata.developers()),
                    join_values(metadata.publishers()),
                    join_values(metadata.genres()),
                    join_values(metadata.presentation_languages()),
                    metadata.presentation_region(),
                    field_provenance_json(metadata),
                    i64::try_from(metadata.resolution_revision()).unwrap_or(i64::MAX),
                    metadata.resolved_at().to_string(),
                ],
            )
            .map_err(map_persistence_error)?;
        refresh_game_library_projection(self.work.transaction_mut()?, &game_id.to_string())?;
        Ok(())
    }

    fn save_settings(&mut self, settings: &MetadataSettings) -> Result<(), PersistenceError> {
        self.work
            .transaction_mut()?
            .execute(
                "UPDATE metadata_settings
                 SET preferred_regions = ?1, preferred_languages = ?2,
                     revision = revision + 1, updated_at = CURRENT_TIMESTAMP
                 WHERE singleton_key = 1",
                params![
                    join_values(settings.preferred_regions()),
                    join_values(settings.preferred_languages()),
                ],
            )
            .map_err(map_persistence_error)?;
        Ok(())
    }

    fn settings(&mut self) -> Result<MetadataSettings, PersistenceError> {
        let row = self
            .work
            .transaction_mut()?
            .query_row(
                "SELECT preferred_regions, preferred_languages
                 FROM metadata_settings WHERE singleton_key = 1",
                [],
                |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
            )
            .optional()
            .map_err(map_persistence_error)?
            .ok_or(PersistenceError::PersistedSettingsInvalid(
                argus_application::PersistedSettingsReason::Missing,
            ))?;
        Ok(MetadataSettings::new(
            split_values(&row.0),
            split_values(&row.1),
        ))
    }

    fn settings_revision(&mut self) -> Result<u64, PersistenceError> {
        let revision: i64 = self
            .work
            .transaction_mut()?
            .query_row(
                "SELECT revision FROM metadata_settings WHERE singleton_key = 1",
                [],
                |row| row.get(0),
            )
            .optional()
            .map_err(map_persistence_error)?
            .ok_or(PersistenceError::PersistedSettingsInvalid(
                argus_application::PersistedSettingsReason::Missing,
            ))?;
        u64::try_from(revision).map_err(|_| PersistenceError::CorruptOrIncompatible)
    }

    fn save_provider_settings(
        &mut self,
        settings: &MetadataProviderSettings,
    ) -> Result<(), PersistenceError> {
        let enabled = settings
            .enabled()
            .iter()
            .map(|provider| provider.as_str())
            .collect::<Vec<_>>()
            .join(",");
        self.work
            .transaction_mut()?
            .execute(
                "UPDATE metadata_provider_settings
                 SET enabled_providers = ?1, revision = revision + 1,
                     updated_at = CURRENT_TIMESTAMP
                 WHERE singleton_key = 1",
                [enabled],
            )
            .map_err(map_persistence_error)?;
        Ok(())
    }

    fn provider_settings(&mut self) -> Result<MetadataProviderSettings, PersistenceError> {
        let value: String = self
            .work
            .transaction_mut()?
            .query_row(
                "SELECT enabled_providers FROM metadata_provider_settings
                 WHERE singleton_key = 1",
                [],
                |row| row.get(0),
            )
            .optional()
            .map_err(map_persistence_error)?
            .ok_or(PersistenceError::PersistedSettingsInvalid(
                argus_application::PersistedSettingsReason::Missing,
            ))?;
        Ok(MetadataProviderSettings::from_enabled(value.split(',')))
    }

    fn provider_metadata_for_content(
        &mut self,
        game_content_id: GameContentId,
    ) -> Result<Vec<ProviderMetadata>, PersistenceError> {
        let connection = self.work.transaction_mut()?;
        let mut statement = connection
            .prepare(
                "SELECT pm.provider_id, pm.external_game_id, pm.provider_revision,
                        pm.region, pm.language, pm.fetched_at, pm.expires_at, pm.title,
                        pm.alternate_titles, pm.description, pm.release_date,
                        pm.developers, pm.publishers, pm.genres, pm.languages,
                        pm.adapter_quality, pm.provenance, mapping.state
                 FROM provider_metadata pm
                 INNER JOIN external_identity_mapping mapping
                    ON mapping.provider_id = pm.provider_id
                   AND mapping.external_game_id = pm.external_game_id
                 WHERE mapping.game_content_id = ?1
                   AND mapping.state IN ('current', 'stale')
                 ORDER BY pm.provider_id, pm.external_game_id, pm.provider_revision",
            )
            .map_err(map_persistence_error)?;
        let rows = statement
            .query_map([game_content_id.to_string()], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, Option<String>>(3)?,
                    row.get::<_, Option<String>>(4)?,
                    row.get::<_, String>(5)?,
                    row.get::<_, Option<String>>(6)?,
                    row.get::<_, Option<String>>(7)?,
                    row.get::<_, String>(8)?,
                    row.get::<_, Option<String>>(9)?,
                    row.get::<_, Option<String>>(10)?,
                    row.get::<_, String>(11)?,
                    row.get::<_, String>(12)?,
                    row.get::<_, String>(13)?,
                    row.get::<_, String>(14)?,
                    row.get::<_, i64>(15)?,
                    row.get::<_, String>(16)?,
                    row.get::<_, String>(17)?,
                ))
            })
            .map_err(map_persistence_error)?;
        let mut metadata = Vec::new();
        for row in rows {
            let (
                provider_id,
                external_game_id,
                provider_revision,
                region,
                language,
                fetched_at,
                expires_at,
                title,
                alternate_titles,
                description,
                release_date,
                developers,
                publishers,
                genres,
                languages,
                adapter_quality,
                provenance,
                mapping_state,
            ) = row.map_err(map_persistence_error)?;
            let provider_id = ProviderId::try_from(provider_id.as_str())
                .map_err(|_| PersistenceError::Internal)?;
            let provider_revision =
                u64::try_from(provider_revision).map_err(|_| PersistenceError::Internal)?;
            let fetched_at = fetched_at
                .parse::<i64>()
                .map_err(|_| PersistenceError::Internal)?;
            let expires_at = expires_at
                .map(|value| value.parse::<i64>().map_err(|_| PersistenceError::Internal))
                .transpose()?;
            let adapter_quality =
                u8::try_from(adapter_quality).map_err(|_| PersistenceError::Internal)?;
            let mapping_state = match mapping_state.as_str() {
                "current" => MappingState::Current,
                "stale" => MappingState::Stale,
                "rejected_by_policy" => MappingState::RejectedByPolicy,
                _ => return Err(PersistenceError::Internal),
            };
            metadata.push(
                ProviderMetadata::new(
                    provider_id,
                    external_game_id,
                    provider_revision,
                    region,
                    language,
                    fetched_at,
                    expires_at,
                    title,
                    split_values(&alternate_titles),
                    description,
                    release_date,
                    split_values(&developers),
                    split_values(&publishers),
                    split_values(&genres),
                    split_values(&languages),
                    adapter_quality,
                    provenance,
                )
                .with_mapping_state(mapping_state),
            );
        }
        Ok(metadata)
    }

    fn mappings_for_content(
        &mut self,
        game_content_id: GameContentId,
    ) -> Result<Vec<ExternalIdentityMapping>, PersistenceError> {
        let connection = self.work.transaction_mut()?;
        let mut statement = connection
            .prepare(
                "SELECT provider_id, external_game_id, external_release_id,
                        provider_platform_id, provider_confidence, match_basis,
                        provider_revision, state, matched_at, last_validated_at
                 FROM external_identity_mapping
                 WHERE game_content_id = ?1
                 ORDER BY provider_id, external_game_id, external_release_id",
            )
            .map_err(map_persistence_error)?;
        let rows = statement
            .query_map([game_content_id.to_string()], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, Option<String>>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, Option<f64>>(4)?,
                    row.get::<_, String>(5)?,
                    row.get::<_, i64>(6)?,
                    row.get::<_, String>(7)?,
                    row.get::<_, String>(8)?,
                    row.get::<_, String>(9)?,
                ))
            })
            .map_err(map_persistence_error)?;
        let mut mappings = Vec::new();
        for row in rows {
            let (
                provider_id,
                external_game_id,
                external_release_id,
                provider_platform_id,
                provider_confidence,
                match_basis,
                provider_revision,
                state,
                matched_at,
                last_validated_at,
            ) = row.map_err(map_persistence_error)?;
            let provider_id = ProviderId::try_from(provider_id.as_str())
                .map_err(|_| PersistenceError::Internal)?;
            let provider_confidence = provider_confidence
                .map(|value| {
                    if value.is_finite() && (0.0..=u16::MAX as f64).contains(&value) {
                        Ok(value as u16)
                    } else {
                        Err(PersistenceError::Internal)
                    }
                })
                .transpose()?;
            let match_basis = match match_basis.as_str() {
                "playmatch_exact_content" => MatchBasis::PlaymatchExactContent,
                "gametdb_exact_native_identifier" => MatchBasis::GameTdbExactNativeIdentifier,
                "existing_exact_mapping" => MatchBasis::ExistingExactMapping,
                "rejected_by_policy" => MatchBasis::RejectedByPolicy,
                _ => return Err(PersistenceError::Internal),
            };
            let state = match state.as_str() {
                "current" => MappingState::Current,
                "stale" => MappingState::Stale,
                "rejected_by_policy" => MappingState::RejectedByPolicy,
                _ => return Err(PersistenceError::Internal),
            };
            let provider_revision =
                u64::try_from(provider_revision).map_err(|_| PersistenceError::Internal)?;
            let matched_at = matched_at
                .parse::<i64>()
                .map_err(|_| PersistenceError::Internal)?;
            let last_validated_at = last_validated_at
                .parse::<i64>()
                .map_err(|_| PersistenceError::Internal)?;
            mappings.push(ExternalIdentityMapping::new(
                game_content_id,
                provider_id,
                external_game_id,
                external_release_id,
                provider_platform_id,
                provider_confidence,
                match_basis,
                provider_revision,
                state,
                matched_at,
                last_validated_at,
            ));
        }
        Ok(mappings)
    }

    fn resolved_metadata_for_game(
        &mut self,
        game_id: argus_domain::GameId,
    ) -> Result<Option<ResolvedMetadata>, PersistenceError> {
        let row = self
            .work
            .transaction_mut()?
            .query_row(
                "SELECT display_title, sort_title, description, release_date,
                        developers, publishers, genres, languages, presentation_region,
                        field_provenance, resolution_revision, resolved_at
                 FROM resolved_metadata WHERE game_id = ?1",
                [game_id.to_string()],
                |row| {
                    Ok((
                        row.get::<_, Option<String>>(0)?,
                        row.get::<_, Option<String>>(1)?,
                        row.get::<_, Option<String>>(2)?,
                        row.get::<_, Option<String>>(3)?,
                        row.get::<_, String>(4)?,
                        row.get::<_, String>(5)?,
                        row.get::<_, String>(6)?,
                        row.get::<_, String>(7)?,
                        row.get::<_, Option<String>>(8)?,
                        row.get::<_, String>(9)?,
                        row.get::<_, i64>(10)?,
                        row.get::<_, String>(11)?,
                    ))
                },
            )
            .optional()
            .map_err(map_persistence_error)?;
        let Some((
            display_title,
            sort_title,
            description,
            release_date,
            developers,
            publishers,
            genres,
            languages,
            presentation_region,
            field_provenance,
            resolution_revision,
            resolved_at,
        )) = row
        else {
            return Ok(None);
        };
        let resolution_revision =
            u64::try_from(resolution_revision).map_err(|_| PersistenceError::Internal)?;
        let resolved_at = resolved_at
            .parse::<i64>()
            .map_err(|_| PersistenceError::Internal)?;
        let field_provenance = parse_field_provenance(&field_provenance)?;
        let provider_id = field_provenance
            .iter()
            .find_map(|value| value.provider_id());
        Ok(Some(ResolvedMetadata::from_persisted(
            display_title,
            sort_title,
            description,
            release_date,
            split_values(&developers),
            split_values(&publishers),
            split_values(&genres),
            presentation_region,
            split_values(&languages),
            field_provenance,
            resolution_revision,
            resolved_at,
            provider_id,
        )))
    }

    fn library_onboarding_progress(
        &mut self,
    ) -> Result<argus_application::LibraryOnboardingProgress, PersistenceError> {
        let row = self
            .work
            .transaction_mut()?
            .query_row(
                "SELECT accepted_privacy_terms_version, accepted_privacy_at_ms,
                        metadata_preferences_confirmed, provider_setup_outcome,
                        completed_at_ms
                 FROM library_onboarding_progress WHERE singleton_key = 1",
                [],
                |row| {
                    Ok((
                        row.get::<_, Option<String>>(0)?,
                        row.get::<_, Option<i64>>(1)?,
                        row.get::<_, i64>(2)?,
                        row.get::<_, String>(3)?,
                        row.get::<_, Option<i64>>(4)?,
                    ))
                },
            )
            .optional()
            .map_err(map_persistence_error)?
            .ok_or(PersistenceError::PersistedSettingsInvalid(
                argus_application::PersistedSettingsReason::Missing,
            ))?;
        let outcome = argus_application::LibraryProviderSetupOutcome::try_from(row.3.as_str())
            .map_err(|_| PersistenceError::CorruptOrIncompatible)?;
        Ok(
            argus_application::LibraryOnboardingProgress::from_persisted(
                row.0,
                row.1,
                row.2 != 0,
                outcome,
                row.4,
            ),
        )
    }

    fn save_library_onboarding_progress(
        &mut self,
        progress: &argus_application::LibraryOnboardingProgress,
    ) -> Result<(), PersistenceError> {
        self.work
            .transaction_mut()?
            .execute(
                "UPDATE library_onboarding_progress
                 SET accepted_privacy_terms_version = ?1,
                     accepted_privacy_at_ms = ?2,
                     metadata_preferences_confirmed = ?3,
                     provider_setup_outcome = ?4,
                     completed_at_ms = ?5
                 WHERE singleton_key = 1",
                rusqlite::params![
                    progress.accepted_privacy_terms_version(),
                    progress.accepted_privacy_at_ms(),
                    i64::from(progress.metadata_preferences_confirmed()),
                    progress.provider_setup_outcome().as_str(),
                    progress.completed_at_ms(),
                ],
            )
            .map_err(map_persistence_error)?;
        Ok(())
    }
}

fn join_values(values: &[String]) -> String {
    values.join("|")
}

fn split_values(value: &str) -> Vec<String> {
    value
        .split('|')
        .filter(|part| !part.is_empty())
        .map(str::to_owned)
        .collect()
}

fn field_provenance_json(metadata: &ResolvedMetadata) -> String {
    let values = metadata
        .field_provenance()
        .iter()
        .map(|provenance| {
            serde_json::json!({
                "field": provenance.field(),
                "provider_id": provenance.provider_id().map(ProviderId::as_str),
                "external_game_id": provenance.external_game_id(),
                "source": provenance.source(),
            })
        })
        .collect::<Vec<_>>();
    serde_json::to_string(&values).unwrap_or_else(|_| "[]".to_owned())
}

fn parse_field_provenance(
    value: &str,
) -> Result<Vec<argus_application::MetadataFieldProvenance>, PersistenceError> {
    let entries = serde_json::from_str::<Vec<serde_json::Value>>(value)
        .map_err(|_| PersistenceError::Internal)?;
    entries
        .into_iter()
        .map(|entry| {
            let field = entry
                .get("field")
                .and_then(serde_json::Value::as_str)
                .ok_or(PersistenceError::Internal)?;
            let provider_id = match entry.get("provider_id") {
                None | Some(serde_json::Value::Null) => None,
                Some(value) => Some(
                    ProviderId::try_from(value.as_str().ok_or(PersistenceError::Internal)?)
                        .map_err(|_| PersistenceError::Internal)?,
                ),
            };
            let external_game_id = entry
                .get("external_game_id")
                .and_then(serde_json::Value::as_str)
                .map(str::to_owned);
            let source = entry
                .get("source")
                .and_then(serde_json::Value::as_str)
                .ok_or(PersistenceError::Internal)?;
            Ok(argus_application::MetadataFieldProvenance::new(
                field,
                provider_id,
                external_game_id,
                source,
            ))
        })
        .collect()
}

fn map_persistence_error(error: rusqlite::Error) -> PersistenceError {
    match operation_error(&error) {
        super::errors::SqliteOperationError::Locked => PersistenceError::DatabaseLocked,
        super::errors::SqliteOperationError::Constraint => PersistenceError::ConstraintViolation,
        super::errors::SqliteOperationError::Application(_) => PersistenceError::Internal,
        super::errors::SqliteOperationError::Failed => PersistenceError::Internal,
    }
}
