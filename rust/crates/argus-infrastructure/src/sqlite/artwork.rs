//! Transaction-bound artwork reference and asset metadata persistence.

use argus_application::{
    ArtworkAsset, ArtworkReference, ArtworkRepository, ArtworkSource, ArtworkType,
    PersistenceError, ProviderId, ResolvedArtwork,
};
use argus_domain::{ArtworkAssetId, GameId};
use rusqlite::params;

use super::errors::operation_error;
use super::logical::refresh_game_library_projection;
use super::unit_of_work::SqliteUnitOfWork;

/// Ephemeral artwork repository view over one active SQLite transaction.
pub struct SqliteArtworkRepository<'scope, 'connection> {
    work: &'scope mut SqliteUnitOfWork<'connection>,
}

impl<'scope, 'connection> SqliteArtworkRepository<'scope, 'connection> {
    /// Creates a repository bound to the active transaction.
    pub(crate) fn new(work: &'scope mut SqliteUnitOfWork<'connection>) -> Self {
        Self { work }
    }
}

impl ArtworkRepository for SqliteArtworkRepository<'_, '_> {
    fn save_reference(&mut self, reference: &ArtworkReference) -> Result<(), PersistenceError> {
        let (source_kind, source_value) = reference.source().kind_and_value();
        self.work
            .transaction_mut()?
            .execute(
                "INSERT INTO artwork_reference
                    (reference_id, provider_id, external_game_id, artwork_type,
                     source_kind, source_value, width, height, format, mime_type,
                     region, language, quality, discovered_at, provider_revision)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12,
                         ?13, ?14, ?15)
                 ON CONFLICT(provider_id, external_game_id, artwork_type, source_kind, source_value)
                 DO UPDATE SET reference_id = excluded.reference_id,
                               width = excluded.width,
                               height = excluded.height,
                               format = excluded.format,
                               mime_type = excluded.mime_type,
                               region = excluded.region,
                               language = excluded.language,
                               quality = excluded.quality,
                               provider_revision = excluded.provider_revision,
                               discovered_at = excluded.discovered_at",
                params![
                    reference.reference_id(),
                    reference.provider_id().as_str(),
                    reference.external_game_id(),
                    reference.artwork_type().as_str(),
                    source_kind,
                    source_value,
                    reference.width().map(i64::from),
                    reference.height().map(i64::from),
                    reference.format(),
                    reference.mime_type(),
                    reference.region(),
                    reference.language(),
                    i64::from(reference.quality()),
                    reference.discovered_at().to_string(),
                    i64::try_from(reference.provider_revision()).unwrap_or(i64::MAX),
                ],
            )
            .map_err(map_persistence_error)?;
        Ok(())
    }

    fn save_resolved_artwork(
        &mut self,
        resolved: &ResolvedArtwork,
    ) -> Result<(), PersistenceError> {
        self.work
            .transaction_mut()?
            .execute(
                "INSERT INTO resolved_artwork
                    (game_id, artwork_type, reference_id, asset_id, ordering,
                     selection_reason, resolution_revision, resolved_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
                 ON CONFLICT(game_id, artwork_type, ordering)
                 DO UPDATE SET reference_id = excluded.reference_id,
                               asset_id = excluded.asset_id,
                               selection_reason = excluded.selection_reason,
                               resolution_revision = excluded.resolution_revision,
                               resolved_at = excluded.resolved_at",
                params![
                    resolved.game_id().to_string(),
                    resolved.artwork_type().as_str(),
                    resolved.reference_id(),
                    resolved.asset_id().map(|asset| asset.to_string()),
                    i64::from(resolved.ordering()),
                    resolved.selection_reason(),
                    i64::try_from(resolved.resolution_revision()).unwrap_or(i64::MAX),
                    resolved.resolved_at().to_string(),
                ],
            )
            .map_err(map_persistence_error)?;
        refresh_game_library_projection(
            self.work.transaction_mut()?,
            &resolved.game_id().to_string(),
        )?;
        Ok(())
    }

    fn replace_resolved_artwork_for_game(
        &mut self,
        game_id: GameId,
        resolved: &[ResolvedArtwork],
    ) -> Result<(), PersistenceError> {
        let transaction = self.work.transaction_mut()?;
        transaction
            .execute(
                "DELETE FROM resolved_artwork WHERE game_id = ?1",
                [game_id.to_string()],
            )
            .map_err(map_persistence_error)?;
        for selection in resolved {
            transaction
                .execute(
                    "INSERT INTO resolved_artwork
                        (game_id, artwork_type, reference_id, asset_id, ordering,
                         selection_reason, resolution_revision, resolved_at)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                    params![
                        selection.game_id().to_string(),
                        selection.artwork_type().as_str(),
                        selection.reference_id(),
                        selection.asset_id().map(|asset| asset.to_string()),
                        i64::from(selection.ordering()),
                        selection.selection_reason(),
                        i64::try_from(selection.resolution_revision()).unwrap_or(i64::MAX),
                        selection.resolved_at().to_string(),
                    ],
                )
                .map_err(map_persistence_error)?;
        }
        refresh_game_library_projection(self.work.transaction_mut()?, &game_id.to_string())?;
        Ok(())
    }

    fn save_asset(&mut self, asset: &ArtworkAsset) -> Result<(), PersistenceError> {
        self.work
            .transaction_mut()?
            .execute(
                "INSERT INTO artwork_asset
                    (asset_id, width, height, mime_type, byte_size, storage_key, created_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, CURRENT_TIMESTAMP)
                 ON CONFLICT(asset_id) DO NOTHING",
                params![
                    asset.asset_id().to_string(),
                    i64::from(asset.width()),
                    i64::from(asset.height()),
                    asset.mime_type(),
                    i64::try_from(asset.byte_size()).unwrap_or(i64::MAX),
                    storage_key(asset.asset_id()),
                ],
            )
            .map_err(map_persistence_error)?;
        Ok(())
    }

    fn references_for_external_game(
        &mut self,
        provider_id: ProviderId,
        external_game_id: &str,
    ) -> Result<Vec<ArtworkReference>, PersistenceError> {
        let connection = self.work.transaction_mut()?;
        let mut statement = connection
            .prepare(
                "SELECT reference_id, artwork_type, source_kind, source_value,
                        width, height, format, mime_type, region, language,
                        quality, discovered_at, provider_revision
                 FROM artwork_reference
                 WHERE provider_id = ?1 AND external_game_id = ?2
                 ORDER BY artwork_type, reference_id",
            )
            .map_err(map_persistence_error)?;
        let rows = statement
            .query_map(params![provider_id.as_str(), external_game_id], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, Option<i64>>(4)?,
                    row.get::<_, Option<i64>>(5)?,
                    row.get::<_, Option<String>>(6)?,
                    row.get::<_, Option<String>>(7)?,
                    row.get::<_, Option<String>>(8)?,
                    row.get::<_, Option<String>>(9)?,
                    row.get::<_, i64>(10)?,
                    row.get::<_, String>(11)?,
                    row.get::<_, i64>(12)?,
                ))
            })
            .map_err(map_persistence_error)?;
        let mut references = Vec::new();
        for row in rows {
            let (
                reference_id,
                artwork_type,
                source_kind,
                source_value,
                width,
                height,
                format,
                mime_type,
                region,
                language,
                quality,
                discovered_at,
                provider_revision,
            ) = row.map_err(map_persistence_error)?;
            let artwork_type =
                artwork_type_from_str(&artwork_type).ok_or(PersistenceError::Internal)?;
            let source = match source_kind.as_str() {
                "credential_free_url" => ArtworkSource::CredentialFreeUrl(source_value),
                "provider_asset_locator" => ArtworkSource::ProviderAssetLocator(source_value),
                _ => return Err(PersistenceError::Internal),
            };
            let width = width
                .map(|value| u32::try_from(value).map_err(|_| PersistenceError::Internal))
                .transpose()?;
            let height = height
                .map(|value| u32::try_from(value).map_err(|_| PersistenceError::Internal))
                .transpose()?;
            let provider_revision =
                u64::try_from(provider_revision).map_err(|_| PersistenceError::Internal)?;
            let discovered_at = discovered_at.parse::<i64>().unwrap_or_default();
            let quality = u8::try_from(quality).map_err(|_| PersistenceError::Internal)?;
            references.push(
                ArtworkReference::new(
                    reference_id,
                    provider_id,
                    external_game_id,
                    artwork_type,
                    source,
                    width,
                    height,
                    format,
                    mime_type,
                    region,
                    language,
                    provider_revision,
                )
                .with_quality(quality)
                .with_discovered_at(discovered_at),
            );
        }
        Ok(references)
    }

    fn resolved_artwork_for_game(
        &mut self,
        game_id: GameId,
    ) -> Result<Vec<ResolvedArtwork>, PersistenceError> {
        let connection = self.work.transaction_mut()?;
        let mut statement = connection
            .prepare(
                "SELECT artwork_type, reference_id, asset_id, ordering,
                        selection_reason, resolution_revision, resolved_at
                 FROM resolved_artwork
                 WHERE game_id = ?1
                 ORDER BY artwork_type, ordering, reference_id",
            )
            .map_err(map_persistence_error)?;
        let rows = statement
            .query_map([game_id.to_string()], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, Option<String>>(2)?,
                    row.get::<_, i64>(3)?,
                    row.get::<_, String>(4)?,
                    row.get::<_, i64>(5)?,
                    row.get::<_, String>(6)?,
                ))
            })
            .map_err(map_persistence_error)?;
        let mut resolved = Vec::new();
        for row in rows {
            let (
                artwork_type,
                reference_id,
                asset_id,
                ordering,
                selection_reason,
                resolution_revision,
                resolved_at,
            ) = row.map_err(map_persistence_error)?;
            let artwork_type =
                artwork_type_from_str(&artwork_type).ok_or(PersistenceError::Internal)?;
            let asset_id = asset_id
                .map(|value| {
                    ArtworkAssetId::try_from(value.as_str()).map_err(|_| PersistenceError::Internal)
                })
                .transpose()?;
            let ordering = u32::try_from(ordering).map_err(|_| PersistenceError::Internal)?;
            let resolution_revision =
                u64::try_from(resolution_revision).map_err(|_| PersistenceError::Internal)?;
            let resolved_at = resolved_at
                .parse::<i64>()
                .map_err(|_| PersistenceError::Internal)?;
            resolved.push(ResolvedArtwork::new(
                game_id,
                artwork_type,
                reference_id,
                asset_id,
                ordering,
                selection_reason,
                resolution_revision,
                resolved_at,
            ));
        }
        Ok(resolved)
    }
}

fn artwork_type_from_str(value: &str) -> Option<ArtworkType> {
    Some(match value {
        "cover_front" => ArtworkType::CoverFront,
        "cover_back" => ArtworkType::CoverBack,
        "cover_spine" => ArtworkType::CoverSpine,
        "screenshot" => ArtworkType::Screenshot,
        "title_screen" => ArtworkType::TitleScreen,
        "logo" => ArtworkType::Logo,
        "icon" => ArtworkType::Icon,
        "background" => ArtworkType::Background,
        "banner" => ArtworkType::Banner,
        "manual" => ArtworkType::Manual,
        _ => return None,
    })
}

fn storage_key(asset_id: ArtworkAssetId) -> String {
    let text = asset_id.to_string();
    format!("artwork-assets/{}/{}/{}", &text[..2], &text[2..4], text)
}

fn map_persistence_error(error: rusqlite::Error) -> PersistenceError {
    match operation_error(&error) {
        super::errors::SqliteOperationError::Locked => PersistenceError::DatabaseLocked,
        super::errors::SqliteOperationError::Constraint => PersistenceError::ConstraintViolation,
        super::errors::SqliteOperationError::Application(_) => PersistenceError::Internal,
        super::errors::SqliteOperationError::Failed => PersistenceError::Internal,
    }
}
