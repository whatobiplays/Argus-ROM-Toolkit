use argus_application::{
    ArtworkReference, ArtworkSource, ArtworkType, CredentialMutationError,
    EnrichmentProviderSession, ExactMatchEvidence, ExternalIdentityMapping, GameContentId,
    HydrationProviderError, HydrationTarget, MappingState, MatchBasis, PlatformId, ProviderId,
    SecureCredentialStore,
};
use argus_domain::GameId;
use argus_infrastructure::providers::{
    GameTdbAdapter, GameTdbSession, PlaymatchAdapter, PlaymatchSession, ProviderAdapterError,
    ProviderRequest, ProviderResponse, ProviderTransport, ProviderTransportError,
    SteamGridDbAdapter, SteamGridDbSession, UreqTransport,
};

#[derive(Clone)]
struct FixtureTransport {
    response: Result<ProviderResponse, ProviderTransportError>,
}

#[derive(Clone, Default)]
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

fn target(identity: &str) -> HydrationTarget {
    HydrationTarget::new(
        GameId::from_bytes([2; 16]).expect("game id"),
        GameContentId::from_bytes([1; 16]).expect("content id"),
        PlatformId::NintendoGb,
        identity,
        "gb",
    )
    .with_observed_at(100)
}

impl ProviderTransport for FixtureTransport {
    fn send(&self, request: ProviderRequest) -> Result<ProviderResponse, ProviderTransportError> {
        assert!(request.url().starts_with("https://fixture.invalid/"));
        self.response.clone()
    }
}

#[test]
fn playmatch_accepts_only_explicit_content_and_platform_binding() {
    let adapter = PlaymatchAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::json(
                200,
                br#"{"matches":[{"external_game_id":"pm-1","platform":"nintendo.gb","identity":"sha256:abc"}]}"#,
            )),
        },
        "https://fixture.invalid/playmatch",
    );

    let matches = adapter
        .match_exact(
            GameContentId::from_bytes([1; 16]).expect("content identity"),
            PlatformId::NintendoGb,
            "sha256:abc",
        )
        .expect("fixture response should parse");

    assert_eq!(matches.len(), 1);
    assert!(matches.iter().any(|match_| {
        matches!(match_, ExactMatchEvidence::Playmatch { external_game_id, .. } if external_game_id == "pm-1")
    }));
}

#[test]
fn gametdb_and_steamgriddb_normalize_provider_native_results() {
    let gametdb = GameTdbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::json(
                200,
                br#"{"game":{"id":"tdb-1","title":"Alpha","region":"us","language":"en","revision":4}}"#,
            )),
        },
        "https://fixture.invalid/gametdb",
    );
    let metadata = gametdb
        .lookup_exact(PlatformId::NintendoGb, "product:DMG-ABCD")
        .expect("fixture response should parse")
        .expect("one exact record");
    assert_eq!(metadata.provider_id(), ProviderId::GameTdb);
    assert_eq!(metadata.title(), Some("Alpha"));
    assert_eq!(metadata.provider_revision(), 4);
    assert_eq!(metadata.provenance(), "gametdb:tdb-1");

    let steamgriddb = SteamGridDbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::json(
                200,
                br#"{"assets":[{"id":"sg-1","type":"cover_front","url":"https://fixture.invalid/asset.png","revision":2,"region":"us","language":"en","width":640,"height":960,"quality":87,"discovered_at":1234}]}"#,
            )),
        },
        "https://fixture.invalid/steamgriddb",
    );
    let artwork = steamgriddb
        .discover_artwork("tdb-1", b"secret")
        .expect("fixture response should parse");
    assert_eq!(artwork.len(), 1);
    assert_eq!(artwork[0].artwork_type(), ArtworkType::CoverFront);
    assert_eq!(artwork[0].source(), "asset:sg-1");
    assert_eq!(artwork[0].region(), Some("us"));
    assert_eq!(artwork[0].language(), Some("en"));
    assert_eq!(artwork[0].width(), Some(640));
    assert_eq!(artwork[0].height(), Some(960));
    assert_eq!(artwork[0].quality(), 87);
    assert_eq!(artwork[0].discovered_at(), 1234);
}

#[test]
fn gametdb_rejects_a_response_bound_to_another_platform_or_identifier() {
    let platform_mismatch = GameTdbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::json(
                200,
                br#"{"game":{"id":"tdb-1","platform":"nintendo.gba","identifier":"product:DMG-ABCD","revision":4}}"#,
            )),
        },
        "https://fixture.invalid/gametdb",
    );
    assert_eq!(
        platform_mismatch
            .lookup_exact(PlatformId::NintendoGb, "product:DMG-ABCD")
            .expect("response should be well formed"),
        None
    );

    let identifier_mismatch = GameTdbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::json(
                200,
                br#"{"game":{"id":"tdb-1","platform":"nintendo.gb","identifier":"product:DMG-OTHER","revision":4}}"#,
            )),
        },
        "https://fixture.invalid/gametdb",
    );
    assert_eq!(
        identifier_mismatch
            .lookup_exact(PlatformId::NintendoGb, "product:DMG-ABCD")
            .expect("response should be well formed"),
        None
    );
}

#[test]
fn gametdb_downloads_discovered_artwork_bytes_through_the_provider_transport() {
    let adapter = GameTdbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::new(200, b"image-bytes".to_vec())),
        },
        "https://fixture.invalid/gametdb",
    );
    let reference = ArtworkReference::new(
        "gametdb:tdb-1:cover",
        ProviderId::GameTdb,
        "tdb-1",
        ArtworkType::CoverFront,
        ArtworkSource::CredentialFreeUrl("https://fixture.invalid/asset.png".to_owned()),
        None,
        None,
        None,
        None,
        None,
        None,
        1,
    );

    let bytes = adapter
        .download_artwork(
            reference.external_game_id(),
            reference.source().kind_and_value().1,
        )
        .expect("fixture artwork should download");

    assert_eq!(bytes, b"image-bytes");
}

#[test]
fn signed_artwork_urls_are_reduced_to_opaque_asset_locators() {
    let adapter = SteamGridDbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::json(
                200,
                br#"{"assets":[{"id":"sg-signed","type":"cover_front","url":"https://fixture.invalid/asset.png?signature=secret&expires=10","revision":3}]}"#,
            )),
        },
        "https://fixture.invalid/steamgriddb",
    );

    let artwork = adapter
        .discover_artwork("tdb-1", b"secret")
        .expect("fixture response should parse");

    assert_eq!(artwork[0].source(), "asset:sg-signed");
}

#[test]
fn malformed_provider_payloads_are_typed_failures() {
    let adapter = PlaymatchAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::json(200, br#"{"matches":"bad"}"#)),
        },
        "https://fixture.invalid/playmatch",
    );

    assert!(
        adapter
            .match_exact(
                GameContentId::from_bytes([1; 16]).expect("content identity"),
                PlatformId::NintendoGb,
                "sha256:abc",
            )
            .is_err()
    );
}

#[test]
fn provider_request_debug_redacts_credentials_and_body_contents() {
    let mut headers = std::collections::BTreeMap::new();
    headers.insert("authorization".to_owned(), "Bearer secret".to_owned());
    let request = ProviderRequest::new("GET", "https://fixture.invalid/asset", headers, b"secret");
    let debug = format!("{request:?}");

    assert!(!debug.contains("secret"));
    assert!(debug.contains("body_len"));
}

#[test]
fn provider_request_debug_redacts_signed_url_query_material() {
    let request = ProviderRequest::new(
        "GET",
        "https://fixture.invalid/asset.png?signature=secret&expires=10",
        std::collections::BTreeMap::new(),
        Vec::new(),
    );
    let debug = format!("{request:?}");

    assert!(!debug.contains("signature=secret"));
    assert!(!debug.contains("expires=10"));
    assert!(debug.contains("fixture.invalid/asset.png"));
}

#[test]
fn artwork_download_rejects_invalid_external_and_opaque_locators() {
    let adapter = GameTdbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::new(200, b"image-bytes".to_vec())),
        },
        "https://fixture.invalid/gametdb",
    );

    assert!(
        adapter
            .download_artwork("tdb-1", "asset:../escape")
            .is_err()
    );
    assert!(
        adapter
            .download_artwork(
                "tdb-1",
                "https://fixture.invalid/asset.png?signature=secret",
            )
            .is_err()
    );
    assert!(
        adapter
            .download_artwork("tdb-1", "https://untrusted.example/asset.png")
            .is_err()
    );
    assert!(
        adapter
            .download_artwork("tdb-1", "https://fixture.invalid:8443/asset.png")
            .is_err()
    );
    assert!(
        adapter
            .download_artwork("tdb-1", "https://user@fixture.invalid/asset.png")
            .is_err()
    );
}

#[test]
fn synchronous_transport_rejects_insecure_and_private_urls_before_network_io() {
    let transport = UreqTransport::new();
    for url in [
        "http://example.com/provider",
        "https://127.0.0.1/provider",
        "https://[::1]/provider",
        "https://user@example.com/provider",
        "https://example.com:444/provider",
    ] {
        assert_eq!(
            transport.send(ProviderRequest::new(
                "GET",
                url,
                std::collections::BTreeMap::new(),
                Vec::new(),
            )),
            Err(ProviderTransportError::Unavailable),
            "URL should be rejected before network I/O: {url}",
        );
    }
}

#[test]
fn production_session_factory_constructs_the_fixed_provider_roster_without_io() {
    let sessions =
        argus_infrastructure::providers::ProductionProviderSessionFactory::new().create_sessions();

    assert_eq!(sessions.len(), 3);
    assert_eq!(
        sessions
            .iter()
            .map(|session| session.provider_id())
            .collect::<Vec<_>>(),
        vec![
            ProviderId::Playmatch,
            ProviderId::GameTdb,
            ProviderId::SteamGridDb
        ]
    );
}

#[test]
fn production_sessions_normalize_each_provider_through_the_shared_session_port() {
    let mut playmatch = PlaymatchSession::new(
        FixtureTransport {
            response: Ok(ProviderResponse::json(
                200,
                br#"{"matches":[{"external_game_id":"pm-1","platform":"nintendo.gb","identity":"sha256:abc"}]}"#,
            )),
        },
        "https://fixture.invalid/playmatch",
    );
    let matches = playmatch
        .match_exact(&target("sha256:abc"))
        .expect("playmatch session response");
    assert_eq!(matches.len(), 1);
    assert_eq!(matches[0].provider_id(), ProviderId::Playmatch);

    let mut gametdb = GameTdbSession::new(
        FixtureTransport {
            response: Ok(ProviderResponse::json(
                200,
                br#"{"game":{"id":"tdb-1","title":"Alpha","region":"us","language":"en","revision":4}}"#,
            )),
        },
        "https://fixture.invalid/gametdb",
    );
    let matches = gametdb
        .match_exact(&target("product:DMG-ABCD"))
        .expect("gametdb session response");
    let metadata = gametdb
        .fetch_metadata(
            &target("product:DMG-ABCD"),
            &ExternalIdentityMapping::new(
                GameContentId::from_bytes([1; 16]).expect("content id"),
                ProviderId::GameTdb,
                "tdb-1",
                None,
                "gb",
                Some(100),
                MatchBasis::GameTdbExactNativeIdentifier,
                4,
                MappingState::Current,
                100,
                100,
            ),
        )
        .expect("gametdb metadata response")
        .expect("metadata record");
    assert_eq!(matches[0].provider_id(), ProviderId::GameTdb);
    assert_eq!(metadata.provider_revision(), 4);

    let mut steamgriddb = SteamGridDbSession::new(
        FixtureTransport {
            response: Ok(ProviderResponse::json(
                200,
                br#"{"assets":[{"id":"sg-1","type":"cover_front","url":"https://fixture.invalid/asset.png","revision":2}]}"#,
            )),
        },
        "https://fixture.invalid/steamgriddb",
        FixtureCredentialStore,
    );
    let references = steamgriddb
        .discover_artwork(&ExternalIdentityMapping::new(
            GameContentId::from_bytes([1; 16]).expect("content id"),
            ProviderId::SteamGridDb,
            "tdb-1",
            None,
            "gb",
            None,
            MatchBasis::ExistingExactMapping,
            1,
            MappingState::Current,
            100,
            100,
        ))
        .expect("steamgriddb session response");
    assert_eq!(references.len(), 1);
    assert_eq!(references[0].source(), "asset:sg-1");
}

#[test]
fn session_transport_rate_limits_and_oversized_downloads_are_typed() {
    let mut session = PlaymatchSession::new(
        FixtureTransport {
            response: Err(ProviderTransportError::RateLimited),
        },
        "https://fixture.invalid/playmatch",
    );
    assert_eq!(
        session.match_exact(&target("sha256:abc")),
        Err(HydrationProviderError::RateLimited)
    );

    let adapter = GameTdbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::new(200, vec![0_u8; 2 * 1024 * 1024 + 1])),
        },
        "https://fixture.invalid/gametdb",
    );
    assert_eq!(
        adapter.download_artwork("tdb-1", "https://fixture.invalid/asset.png"),
        Err(ProviderAdapterError::Transport(
            ProviderTransportError::ResponseTooLarge,
        ))
    );
}
