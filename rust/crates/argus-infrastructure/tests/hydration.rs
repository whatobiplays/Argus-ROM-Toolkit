use std::collections::BTreeSet;

use argus_application::{
    ArtworkAsset, ArtworkAssetId, ArtworkAssetStore, ArtworkCandidate, ArtworkReference,
    ArtworkRepository, ArtworkResolutionPolicy, ArtworkType, CredentialMutationError,
    CredentialValidationError, CredentialValidator, EnrichmentProviderSession,
    EnrichmentUnitOfWork, ExternalIdentityMapping, HydrationCoordinator, HydrationProviderError,
    HydrationTarget, MappingState, MatchBasis, MetadataProviderRegistry, MetadataProviderService,
    MetadataProviderSettings, MetadataRepository, MetadataResolutionPolicy, OperationContext,
    OperationName, PlatformId, ProviderId, ProviderMetadata, ProviderReadinessState,
    SecureCredentialStore, SubsystemName, TraceId, UnitOfWorkFactory,
};
use argus_domain::{GameContentId, GameId};
use argus_infrastructure::sqlite::SqliteDatabaseExecutor;

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(21).expect("trace"),
        SubsystemName::try_from("test").expect("subsystem"),
        OperationName::try_from("hydration").expect("operation"),
    )
}

#[derive(Default)]
struct FixtureCredentialStore;

impl SecureCredentialStore for FixtureCredentialStore {
    fn set(
        &mut self,
        _provider_id: ProviderId,
        _secret: &[u8],
    ) -> Result<(), CredentialMutationError> {
        Ok(())
    }

    fn remove(&mut self, _provider_id: ProviderId) -> Result<(), CredentialMutationError> {
        Ok(())
    }

    fn is_configured(&mut self, _provider_id: ProviderId) -> Result<bool, CredentialMutationError> {
        Ok(true)
    }

    fn with_secret<T>(
        &mut self,
        _provider_id: ProviderId,
        operation: &mut dyn FnMut(&[u8]) -> T,
    ) -> Result<T, CredentialMutationError> {
        Ok(operation(b"fixture-secret"))
    }
}

struct FixtureCredentialValidator;

impl CredentialValidator for FixtureCredentialValidator {
    fn validate(&self, _secret: &[u8]) -> Result<(), CredentialValidationError> {
        Ok(())
    }
}

struct FixtureProviderSession {
    provider_id: ProviderId,
    artwork_bytes: Vec<u8>,
}

impl EnrichmentProviderSession for FixtureProviderSession {
    fn provider_id(&self) -> ProviderId {
        self.provider_id
    }

    fn match_exact(
        &mut self,
        _target: &HydrationTarget,
    ) -> Result<Vec<argus_application::HydrationMappingCandidate>, HydrationProviderError> {
        Ok(Vec::new())
    }

    fn fetch_metadata(
        &mut self,
        _target: &HydrationTarget,
        mapping: &ExternalIdentityMapping,
    ) -> Result<Option<ProviderMetadata>, HydrationProviderError> {
        Ok(Some(ProviderMetadata::new(
            ProviderId::GameTdb,
            mapping.external_game_id(),
            2,
            Some("us".to_owned()),
            Some("en".to_owned()),
            100,
            None,
            Some("Fixture Game".to_owned()),
            Vec::new(),
            Some("A deterministic fixture description".to_owned()),
            None,
            Vec::new(),
            Vec::new(),
            vec!["action".to_owned()],
            vec!["en".to_owned()],
            100,
            "fixture:gametdb:tdb-1",
        )))
    }

    fn discover_artwork(
        &mut self,
        _mapping: &ExternalIdentityMapping,
    ) -> Result<Vec<ArtworkCandidate>, HydrationProviderError> {
        Ok(vec![
            ArtworkCandidate::new(
                self.provider_id,
                "cover-1",
                ArtworkType::CoverFront,
                "https://fixture.invalid/cover.png",
                2,
            )
            .with_details(Some("us"), Some("en"), Some(640), Some(960), 87)
            .with_discovered_at(150),
        ])
    }

    fn download_artwork(
        &mut self,
        _reference: &ArtworkReference,
    ) -> Result<Vec<u8>, HydrationProviderError> {
        Ok(self.artwork_bytes.clone())
    }
}

struct FixtureAssetStore;

impl ArtworkAssetStore for FixtureAssetStore {
    fn store(
        &self,
        bytes: &[u8],
    ) -> Result<ArtworkAsset, argus_application::ArtworkAssetStoreError> {
        assert!(!bytes.is_empty());
        Ok(ArtworkAsset::new(
            ArtworkAssetId::from_bytes([9; 32]).expect("asset id"),
            1,
            1,
            "image/png",
            bytes.len() as u64,
        ))
    }
}

fn seed_logical_rows(
    executor: &SqliteDatabaseExecutor,
    game_id: GameId,
    content_id: GameContentId,
) {
    let sql = format!(
        "INSERT INTO game_content
            (game_content_id, platform_id, content_type, presence_state,
             identification_state, grouping_revision, created_at, updated_at)
         VALUES ('{content_id}', 'nintendo.gb', 'CartridgeImage', 'available',
                 'identified', 1, 'now', 'now');
         INSERT INTO game
            (game_id, platform_id, lifecycle_state, grouping_revision, fallback_title,
             fallback_title_provenance, hydration_state, created_at, updated_at)
         VALUES ('{game_id}', 'nintendo.gb', 'active', 1, 'Fixture fallback',
                 'local_fallback', 'partially_hydrated', 'now', 'now');"
    );
    executor
        .with_connection_for_tests(context(), move |connection| connection.execute_batch(&sql))
        .expect("seed logical rows");
}

#[test]
fn coordinator_commits_provider_results_then_resolves_and_attaches_artwork_asset() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let game_id = GameId::from_bytes([5; 16]).expect("game id");
    let content_id = GameContentId::from_bytes([4; 16]).expect("content id");
    seed_logical_rows(&executor, game_id, content_id);

    let mapping = ExternalIdentityMapping::new(
        content_id,
        ProviderId::GameTdb,
        "tdb-1",
        None,
        "gb",
        None,
        MatchBasis::ExistingExactMapping,
        1,
        MappingState::Current,
        100,
        100,
    );
    let target = HydrationTarget::new(
        game_id,
        content_id,
        PlatformId::NintendoGb,
        "product:fixture",
        "gb",
    )
    .with_existing_mappings(vec![mapping.clone()])
    .with_observed_at(100);

    let mut credential_service =
        MetadataProviderService::new(FixtureCredentialStore, FixtureCredentialValidator);
    let credential_readiness = credential_service
        .set_steamgriddb_credential(b"fixture")
        .expect("fixture credential");
    assert_eq!(credential_readiness.state(), ProviderReadinessState::Ready);
    let registry = MetadataProviderRegistry::production();
    let readiness =
        registry.readiness_projection(&MetadataProviderSettings::default(), credential_readiness);
    let metadata_policy =
        MetadataResolutionPolicy::new(BTreeSet::from([ProviderId::GameTdb]), ["us"], ["en"]);
    let mut sessions: Vec<Box<dyn EnrichmentProviderSession>> =
        vec![Box::new(FixtureProviderSession {
            provider_id: ProviderId::GameTdb,
            artwork_bytes: vec![137, 80, 78, 71],
        })];
    let coordinator = HydrationCoordinator::new(executor.clone());

    let report = coordinator
        .hydrate(
            &context(),
            target,
            metadata_policy,
            ArtworkResolutionPolicy::default(),
            &registry,
            &readiness,
            &mut sessions,
            &FixtureAssetStore,
            200,
        )
        .expect("hydration should commit independently");

    assert_eq!(
        report.resolved_metadata().display_title(),
        Some("Fixture Game")
    );
    assert_eq!(report.resolved_artwork().len(), 1);
    assert_eq!(
        report.resolved_artwork()[0].asset_id(),
        Some(ArtworkAssetId::from_bytes([9; 32]).expect("asset id"))
    );
    assert!(report.issues().is_empty());

    executor
        .execute(&context(), move |mut work| {
            let metadata = work
                .metadata()
                .resolved_metadata_for_game(game_id)?
                .expect("resolved metadata persisted");
            assert_eq!(metadata.display_title(), Some("Fixture Game"));
            let artwork = work.artwork().resolved_artwork_for_game(game_id)?;
            assert_eq!(artwork.len(), 1);
            assert_eq!(
                artwork[0].asset_id(),
                report.resolved_artwork()[0].asset_id()
            );
            let references = work
                .artwork()
                .references_for_external_game(ProviderId::GameTdb, "tdb-1")?;
            assert_eq!(references.len(), 1);
            assert_eq!(references[0].region(), Some("us"));
            assert_eq!(references[0].language(), Some("en"));
            assert_eq!(references[0].width(), Some(640));
            assert_eq!(references[0].height(), Some(960));
            assert_eq!(
                references[0].source().kind_and_value(),
                ("provider_asset_locator", "asset:cover-1")
            );
            work.commit()
        })
        .expect("committed enrichment should be readable");

    let mut second_policy = ArtworkResolutionPolicy::default();
    second_policy.set_enabled(ProviderId::GameTdb, false);
    let mut second_sessions: Vec<Box<dyn EnrichmentProviderSession>> =
        vec![Box::new(FixtureProviderSession {
            provider_id: ProviderId::GameTdb,
            artwork_bytes: vec![137, 80, 78, 71],
        })];
    let second_report = HydrationCoordinator::new(executor.clone())
        .hydrate(
            &context(),
            HydrationTarget::new(
                game_id,
                content_id,
                PlatformId::NintendoGb,
                "product:fixture",
                "gb",
            )
            .with_existing_mappings(vec![mapping])
            .with_observed_at(300),
            MetadataResolutionPolicy::new(BTreeSet::from([ProviderId::GameTdb]), ["us"], ["en"]),
            second_policy,
            &registry,
            &readiness,
            &mut second_sessions,
            &FixtureAssetStore,
            300,
        )
        .expect("local resolution should replace disabled artwork selections");
    assert!(second_report.resolved_artwork().is_empty());
    executor
        .execute(&context(), move |mut work| {
            assert!(
                work.artwork()
                    .resolved_artwork_for_game(game_id)?
                    .is_empty()
            );
            work.commit()
        })
        .expect("replaced artwork should be readable");

    executor.shutdown().expect("shutdown");
}

#[test]
fn artwork_only_provider_enriches_an_accepted_mapping_without_creating_one() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let game_id = GameId::from_bytes([6; 16]).expect("game id");
    let content_id = GameContentId::from_bytes([7; 16]).expect("content id");
    seed_logical_rows(&executor, game_id, content_id);

    let mapping = ExternalIdentityMapping::new(
        content_id,
        ProviderId::GameTdb,
        "tdb-1",
        None,
        "gb",
        None,
        MatchBasis::ExistingExactMapping,
        1,
        MappingState::Current,
        100,
        100,
    );
    let target = HydrationTarget::new(
        game_id,
        content_id,
        PlatformId::NintendoGb,
        "product:fixture",
        "gb",
    )
    .with_existing_mappings(vec![mapping])
    .with_observed_at(100);

    let mut credential_service =
        MetadataProviderService::new(FixtureCredentialStore, FixtureCredentialValidator);
    let credential_readiness = credential_service
        .set_steamgriddb_credential(b"fixture")
        .expect("fixture credential");
    let registry = MetadataProviderRegistry::production();
    let readiness =
        registry.readiness_projection(&MetadataProviderSettings::default(), credential_readiness);
    let metadata_policy =
        MetadataResolutionPolicy::new(BTreeSet::from([ProviderId::GameTdb]), ["us"], ["en"]);
    let mut sessions: Vec<Box<dyn EnrichmentProviderSession>> =
        vec![Box::new(FixtureProviderSession {
            provider_id: ProviderId::SteamGridDb,
            artwork_bytes: vec![137, 80, 78, 71],
        })];

    let report = HydrationCoordinator::new(executor.clone())
        .hydrate(
            &context(),
            target,
            metadata_policy,
            ArtworkResolutionPolicy::default(),
            &registry,
            &readiness,
            &mut sessions,
            &FixtureAssetStore,
            200,
        )
        .expect("artwork-only hydration should succeed");

    assert_eq!(report.mappings().len(), 1);
    assert_eq!(report.mappings()[0].provider_id(), ProviderId::GameTdb);
    assert_eq!(report.resolved_artwork().len(), 1);
    assert_eq!(
        report.resolved_artwork()[0].asset_id(),
        Some(ArtworkAssetId::from_bytes([9; 32]).expect("asset id"))
    );
    assert!(report.issues().is_empty());

    executor.shutdown().expect("shutdown");
}
