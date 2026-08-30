use argus_application::{
    ArtworkReference, ArtworkSource, ArtworkType, CredentialMutationError, CredentialValidator,
    EnrichmentProviderSession, ExactMatchEvidence, ExternalIdentityMapping, GameContentId,
    HydrationProviderError, HydrationTarget, MappingState, MatchBasis, PlatformId, ProviderId,
    SecureCredentialStore,
};
use argus_domain::GameId;
use argus_infrastructure::providers::{
    GameTdbAdapter, GameTdbSession, PlaymatchAdapter, PlaymatchSession, ProviderAdapterError,
    ProviderRequest, ProviderResponse, ProviderTransport, ProviderTransportError,
    SteamGridDbAdapter, SteamGridDbCredentialValidator, SteamGridDbSession, UreqTransport,
};
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

const PLAYMATCH_SHA256: &str = "2920c755dea482c7e465cce62ee54ccdc103181b18a867fac289d0cd68b5d262";
const PLAYMATCH_GAME_ID: &str = "c3c628c2-74f4-45a5-8a98-940b30362067";
const STEAMGRIDDB_GAME_ID: &str = "5249689";
const STEAMGRIDDB_GRID_ID: &str = "740598";
const STEAMGRIDDB_GRID_URL: &str =
    "https://cdn2.steamgriddb.com/grid/28d7f95b770c7afa95e36882b4797c14.png";
const STEAMGRIDDB_GRID_THUMB_URL: &str =
    "https://cdn2.steamgriddb.com/thumb/28d7f95b770c7afa95e36882b4797c14.jpg";
const PLAYMATCH_V2_RELATIONS: &[u8] = br#"{
    "gameMatchType":"SHA256",
    "game":{"id":"c3c628c2-74f4-45a5-8a98-940b30362067","name":"10-Pin Bowling (USA) (Proto)","description":"10-Pin Bowling (USA) (Proto)","categories":["Games","Preproduction"],"currentInLatestDat":true,"lastSeenDatVersion":"20260707-013717","lastSeenDatFileImportId":"50fc8551-1678-4249-9641-a0870fd88e4a","createdAt":"2024-08-27T16:46:07.328265Z","updatedAt":"2026-07-09T12:09:20.215515Z"},
    "platform":{"id":"224cc231-e9ca-4bf7-80a2-cf383885d7b2","name":"Game Boy","companyId":"f030ed59-c6f1-4a44-95fc-1fbb2474e523","updatedAt":"2024-08-27T16:46:07.287465Z","createdAt":"2024-08-27T16:46:07.287465Z"},
    "gameFiles":[{"id":"f18eeaf0-b334-48b5-83b0-524b940470d5","gameId":"c3c628c2-74f4-45a5-8a98-940b30362067","fileName":"10-Pin Bowling (USA) (Proto).gb","fileSizeInBytes":131072,"crc":"9a024415","md5":"7616285ddcb0a1834770cacd20c2b2fe","sha1":"952d154dd2c6189ef4b786ae37bd7887c8ca9037","sha256":"2920c755dea482c7e465cce62ee54ccdc103181b18a867fac289d0cd68b5d262","currentInLatestDat":true,"lastSeenDatVersion":"20260707-013717","lastSeenDatFileImportId":"50fc8551-1678-4249-9641-a0870fd88e4a","createdAt":"2024-08-27T16:46:07.339357Z","updatedAt":"2026-07-09T12:09:18.588591Z"}],
    "additionalMatches":null
}"#;

#[derive(Clone)]
struct FixtureTransport {
    response: Result<ProviderResponse, ProviderTransportError>,
}

#[derive(Clone)]
struct RecordingTransport {
    response: Result<ProviderResponse, ProviderTransportError>,
    requests: Arc<Mutex<Vec<ProviderRequest>>>,
}

#[derive(Clone)]
struct SequenceTransport {
    responses: Arc<Mutex<VecDeque<Result<ProviderResponse, ProviderTransportError>>>>,
    requests: Arc<Mutex<Vec<ProviderRequest>>>,
}

#[derive(Clone, Default)]
struct FixtureCredentialStore;

#[derive(Clone, Default)]
struct UnavailableCredentialStore;

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

impl SecureCredentialStore for UnavailableCredentialStore {
    fn set(
        &mut self,
        _provider_id: ProviderId,
        _secret: &[u8],
    ) -> Result<(), CredentialMutationError> {
        Err(CredentialMutationError::StoreUnavailable)
    }

    fn remove(&mut self, _provider_id: ProviderId) -> Result<(), CredentialMutationError> {
        Err(CredentialMutationError::StoreUnavailable)
    }

    fn is_configured(&mut self, _provider_id: ProviderId) -> Result<bool, CredentialMutationError> {
        Err(CredentialMutationError::StoreUnavailable)
    }

    fn with_secret<T>(
        &mut self,
        _provider_id: ProviderId,
        _operation: &mut dyn FnMut(&[u8]) -> T,
    ) -> Result<T, CredentialMutationError> {
        Err(CredentialMutationError::StoreUnavailable)
    }
}

#[derive(Clone, Default)]
struct NoNetworkTransport;

impl ProviderTransport for NoNetworkTransport {
    fn send(&self, _request: ProviderRequest) -> Result<ProviderResponse, ProviderTransportError> {
        panic!("credential failure must stop before provider transport");
    }
}

fn target_for(
    platform_id: PlatformId,
    provider_platform_id: &str,
    identity: &str,
) -> HydrationTarget {
    HydrationTarget::new(
        GameId::from_bytes([2; 16]).expect("game id"),
        GameContentId::from_bytes([1; 16]).expect("content id"),
        platform_id,
        identity,
        provider_platform_id,
    )
    .with_observed_at(100)
}

fn target(identity: &str) -> HydrationTarget {
    target_for(PlatformId::NintendoGb, "nintendo.gb", identity)
}

impl ProviderTransport for FixtureTransport {
    fn send(&self, request: ProviderRequest) -> Result<ProviderResponse, ProviderTransportError> {
        assert!(request.url().starts_with("https://fixture.invalid/"));
        self.response.clone()
    }
}

impl ProviderTransport for RecordingTransport {
    fn send(&self, request: ProviderRequest) -> Result<ProviderResponse, ProviderTransportError> {
        self.requests
            .lock()
            .expect("request recorder lock")
            .push(request);
        self.response.clone()
    }
}

impl SequenceTransport {
    fn new(
        responses: impl IntoIterator<Item = Result<ProviderResponse, ProviderTransportError>>,
    ) -> Self {
        Self {
            responses: Arc::new(Mutex::new(responses.into_iter().collect())),
            requests: Arc::new(Mutex::new(Vec::new())),
        }
    }

    fn requests(&self) -> Vec<ProviderRequest> {
        self.requests.lock().expect("request recorder lock").clone()
    }
}

impl ProviderTransport for SequenceTransport {
    fn send(&self, request: ProviderRequest) -> Result<ProviderResponse, ProviderTransportError> {
        self.requests
            .lock()
            .expect("request recorder lock")
            .push(request);
        self.responses
            .lock()
            .expect("response queue lock")
            .pop_front()
            .unwrap_or(Err(ProviderTransportError::Unavailable))
    }
}

fn steamgriddb_response(asset_id: u64, url: &str) -> ProviderResponse {
    ProviderResponse::json(
        200,
        format!(
            r#"{{
                "success":true,
                "page":0,
                "total":1,
                "limit":50,
                "data":[{{
                    "id":{asset_id},
                    "score":0,
                    "style":"alternate",
                    "url":"{url}",
                    "thumb":"{STEAMGRIDDB_GRID_THUMB_URL}",
                    "tags":[],
                    "author":{{"name":"fixture-author","steam64":"76561198000000000","avatar":"https://avatars.steamstatic.com/fixture.jpg"}}
                }}]
            }}"#
        )
        .as_bytes(),
    )
}

fn steamgriddb_empty_response() -> ProviderResponse {
    ProviderResponse::json(
        200,
        br#"{"success":true,"page":0,"total":0,"limit":50,"data":[]}"#,
    )
}

#[test]
fn playmatch_accepts_only_explicit_content_and_platform_binding() {
    let adapter = PlaymatchAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::json(200, PLAYMATCH_V2_RELATIONS)),
        },
        "https://fixture.invalid/playmatch",
    );

    let matches = adapter
        .match_exact(
            GameContentId::from_bytes([1; 16]).expect("content identity"),
            PlatformId::NintendoGb,
            PLAYMATCH_SHA256,
        )
        .expect("fixture response should parse");

    assert_eq!(matches.len(), 1);
    assert!(matches.iter().any(|match_| {
        matches!(match_, ExactMatchEvidence::Playmatch { external_game_id, .. } if external_game_id == PLAYMATCH_GAME_ID)
    }));
}

#[test]
fn playmatch_v2_relations_response_produces_sha256_exact_evidence() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let adapter = PlaymatchAdapter::new(
        RecordingTransport {
            response: Ok(ProviderResponse::json(
                200,
                br#"{
                    "gameMatchType":"SHA256",
                    "game":{"id":"c3c628c2-74f4-45a5-8a98-940b30362067","name":"10-Pin Bowling (USA) (Proto)"},
                    "platform":{"id":"224cc231-e9ca-4bf7-80a2-cf383885d7b2","name":"Game Boy"},
                    "gameFiles":[{"gameId":"c3c628c2-74f4-45a5-8a98-940b30362067","fileName":"10-Pin Bowling (USA) (Proto).gb","fileSizeInBytes":131072,"sha256":"2920c755dea482c7e465cce62ee54ccdc103181b18a867fac289d0cd68b5d262"}],
                    "additionalMatches":null
                }"#,
            )),
            requests: Arc::clone(&requests),
        },
        "https://fixture.invalid/playmatch",
    );

    let identity = "2920c755dea482c7e465cce62ee54ccdc103181b18a867fac289d0cd68b5d262";
    let matches = adapter
        .match_exact(
            GameContentId::from_bytes([1; 16]).expect("content identity"),
            PlatformId::NintendoGb,
            identity,
        )
        .expect("v2 relations fixture should parse");

    assert_eq!(matches.len(), 1);
    assert!(matches.iter().any(|match_| {
        matches!(match_, ExactMatchEvidence::Playmatch {
            external_game_id,
            submitted_identity,
            response_identity,
            ..
        } if external_game_id == "c3c628c2-74f4-45a5-8a98-940b30362067"
            && submitted_identity == identity
            && response_identity == identity)
    }));

    let requests = requests.lock().expect("request recorder lock");
    assert_eq!(requests.len(), 1);
    assert_eq!(requests[0].method(), "GET");
    assert!(requests[0].body().is_empty());
    assert_eq!(
        requests[0].url(),
        "https://fixture.invalid/playmatch/identify/relations?fileName=argus-probe.rom&fileSize=0&sha256=2920c755dea482c7e465cce62ee54ccdc103181b18a867fac289d0cd68b5d262"
    );
}

#[test]
fn playmatch_v2_preserves_same_platform_cohashed_matches_for_application_ambiguity() {
    let response = format!(
        r#"{{
            "gameMatchType":"SHA256",
            "game":{{"id":"primary-game"}},
            "platform":{{"name":"Game Boy"}},
            "gameFiles":[{{"gameId":"primary-game","sha256":"{PLAYMATCH_SHA256}"}}],
            "additionalMatches":[
                {{"game":{{"id":"secondary-game"}},"platform":{{"name":"Game Boy"}},"gameFiles":[{{"gameId":"secondary-game","sha256":"{PLAYMATCH_SHA256}"}}]}},
                {{"game":{{"id":"other-platform-game"}},"platform":{{"name":"Nintendo DS"}},"gameFiles":[{{"gameId":"other-platform-game","sha256":"{PLAYMATCH_SHA256}"}}]}}
            ]
        }}"#
    );
    let adapter = PlaymatchAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::new(200, response.into_bytes())),
        },
        "https://fixture.invalid/playmatch",
    );

    let matches = adapter
        .match_exact(
            GameContentId::from_bytes([1; 16]).expect("content identity"),
            PlatformId::NintendoGb,
            PLAYMATCH_SHA256,
        )
        .expect("co-hashed response should parse");

    assert_eq!(matches.len(), 2);
    assert!(matches.iter().any(|match_| {
        matches!(match_, ExactMatchEvidence::Playmatch { external_game_id, .. } if external_game_id == "primary-game")
    }));
    assert!(matches.iter().any(|match_| {
        matches!(match_, ExactMatchEvidence::Playmatch { external_game_id, .. } if external_game_id == "secondary-game")
    }));
    assert!(!matches.iter().any(|match_| {
        matches!(match_, ExactMatchEvidence::Playmatch { external_game_id, .. } if external_game_id == "other-platform-game")
    }));
}

#[test]
fn playmatch_fallback_and_no_match_results_never_become_exact_evidence() {
    for body in [
        br#"{"gameMatchType":"NoMatch"}"#.as_slice(),
        br#"{"gameMatchType":"FileNameAndSize"}"#.as_slice(),
    ] {
        let adapter = PlaymatchAdapter::new(
            FixtureTransport {
                response: Ok(ProviderResponse::json(200, body)),
            },
            "https://fixture.invalid/playmatch",
        );
        assert!(
            adapter
                .match_exact(
                    GameContentId::from_bytes([1; 16]).expect("content identity"),
                    PlatformId::NintendoGb,
                    PLAYMATCH_SHA256,
                )
                .expect("non-exact outcome should be handled")
                .is_empty()
        );
    }
}

#[test]
fn gametdb_official_ds_catalog_resolves_an_exact_prefixed_identifier() {
    let adapter = GameTdbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::new(
                200,
                b"TITLES = https://www.gametdb.com (type: DS language: EN version: 20260829161155)\nA2DE = New Super Mario Bros.\nA2DP = New Super Mario Bros. (Demo)\t\n".to_vec(),
            )),
        },
        "https://fixture.invalid/gametdb",
    );

    let metadata = adapter
        .lookup_exact(PlatformId::NintendoNds, "product:A2DE")
        .expect("official catalog fixture should parse")
        .expect("one exact DS record");

    assert_eq!(metadata.provider_id(), ProviderId::GameTdb);
    assert_eq!(metadata.external_game_id(), "A2DE");
    assert_eq!(metadata.title(), Some("New Super Mario Bros."));
    assert_eq!(metadata.provider_revision(), 20_260_829_161_155);
    assert_eq!(metadata.provenance(), "gametdb:A2DE");
}

#[test]
fn gametdb_official_ds_catalog_uses_the_official_artwork_locator() {
    let adapter = GameTdbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::new(
                200,
                b"TITLES = https://www.gametdb.com (type: DS language: EN version: 1)\nA2DE = New Super Mario Bros.\n".to_vec(),
            )),
        },
        "https://fixture.invalid/gametdb",
    );

    let artwork = adapter
        .discover_artwork("A2DE")
        .expect("known DS identifier should expose official artwork");

    assert_eq!(artwork.len(), 1);
    assert_eq!(artwork[0].artwork_type(), ArtworkType::CoverFront);
    assert_eq!(artwork[0].external_asset_id(), "cover:US:A2DE");
    assert_eq!(artwork[0].source(), "asset:cover:US:A2DE");
}

#[test]
fn gametdb_rejects_non_ds_platforms_as_an_unsupported_capability() {
    let adapter = GameTdbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::new(
                200,
                b"TITLES = https://www.gametdb.com (type: DS language: EN version: 1)\nA2DE = New Super Mario Bros.\n".to_vec(),
            )),
        },
        "https://fixture.invalid/gametdb",
    );

    assert_eq!(
        adapter.lookup_exact(PlatformId::NintendoGb, "product:A2DE"),
        Err(ProviderAdapterError::UnsupportedCapability)
    );
}

#[test]
fn gametdb_catalog_rejects_malformed_headers_records_duplicates_and_oversized_bodies() {
    for body in [
        "TITLES = https://www.gametdb.com (type: GB language: EN version: 1)\nA2DE = Alpha\n",
        "TITLES = https://www.gametdb.com (type: DS language: EN version: 1)\nnot-a-record\n",
        "TITLES = https://www.gametdb.com (type: DS language: EN version: 1)\nA2DE = Alpha\nA2DE = Duplicate\n",
        &format!(
            "TITLES = https://www.gametdb.com (type: DS language: EN version: 1)\nA2DE = {}\n",
            "x".repeat(2049)
        ),
    ] {
        let adapter = GameTdbAdapter::new(
            FixtureTransport {
                response: Ok(ProviderResponse::new(200, body.as_bytes().to_vec())),
            },
            "https://fixture.invalid/gametdb",
        );
        assert_eq!(
            adapter.lookup_exact(PlatformId::NintendoNds, "native:A2DE"),
            Err(ProviderAdapterError::InvalidResponse)
        );
    }

    let adapter = GameTdbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::new(200, vec![0_u8; 2 * 1024 * 1024 + 1])),
        },
        "https://fixture.invalid/gametdb",
    );
    assert_eq!(
        adapter.lookup_exact(PlatformId::NintendoNds, "native:A2DE"),
        Err(ProviderAdapterError::Transport(
            ProviderTransportError::ResponseTooLarge,
        ))
    );
}

#[test]
fn gametdb_downloads_official_cover_asset_through_the_provider_transport() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let adapter = GameTdbAdapter::new(
        RecordingTransport {
            response: Ok(ProviderResponse::new(200, b"image-bytes".to_vec())),
            requests: Arc::clone(&requests),
        },
        "https://fixture.invalid/gametdb",
    );

    let bytes = adapter
        .download_artwork("A2DE", "asset:cover:US:A2DE")
        .expect("official cover asset should download");
    assert_eq!(bytes, b"image-bytes");

    let requests = requests.lock().expect("request recorder lock");
    assert_eq!(requests.len(), 1);
    assert_eq!(requests[0].method(), "GET");
    assert_eq!(
        requests[0].url(),
        "https://art.gametdb.com/ds/cover/US/A2DE.jpg"
    );
    assert!(requests[0].body().is_empty());
}

#[test]
fn gametdb_rejects_mismatched_or_unproven_artwork_locators() {
    let adapter = GameTdbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::new(200, b"image-bytes".to_vec())),
        },
        "https://fixture.invalid/gametdb",
    );

    for source in [
        "asset:cover:US:A2DP",
        "asset:cover:EN:A2DE",
        "asset:box:US:A2DE",
        "asset:cover:XX:A2DE",
    ] {
        assert_eq!(
            adapter.download_artwork("A2DE", source),
            Err(ProviderAdapterError::InvalidResponse),
            "locator should be rejected: {source}"
        );
    }
}

#[test]
fn gametdb_and_steamgriddb_normalize_provider_native_results() {
    let gametdb = GameTdbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::new(
                200,
                b"TITLES = https://www.gametdb.com (type: DS language: EN version: 4)\nA2DE = Alpha\n".to_vec(),
            )),
        },
        "https://fixture.invalid/gametdb",
    );
    let metadata = gametdb
        .lookup_exact(PlatformId::NintendoNds, "product:A2DE")
        .expect("fixture response should parse")
        .expect("one exact record");
    assert_eq!(metadata.provider_id(), ProviderId::GameTdb);
    assert_eq!(metadata.title(), Some("Alpha"));
    assert_eq!(metadata.provider_revision(), 4);
    assert_eq!(metadata.provenance(), "gametdb:A2DE");

    let transport = SequenceTransport::new([
        Ok(steamgriddb_response(
            STEAMGRIDDB_GRID_ID.parse().expect("numeric fixture id"),
            STEAMGRIDDB_GRID_URL,
        )),
        Ok(steamgriddb_response(
            740599,
            "https://cdn2.steamgriddb.com/hero/fixture-hero.png",
        )),
        Ok(steamgriddb_response(
            740600,
            "https://cdn2.steamgriddb.com/logo/fixture-logo.png",
        )),
        Ok(steamgriddb_response(
            740601,
            "https://cdn2.steamgriddb.com/icon/fixture-icon.png",
        )),
    ]);
    let steamgriddb =
        SteamGridDbAdapter::new(transport.clone(), "https://fixture.invalid/steamgriddb");
    let artwork = steamgriddb
        .discover_artwork(STEAMGRIDDB_GAME_ID, b"secret")
        .expect("v2 fixture responses should parse");
    assert_eq!(artwork.len(), 4);
    assert_eq!(artwork[0].artwork_type(), ArtworkType::CoverFront);
    assert_eq!(artwork[0].external_asset_id(), STEAMGRIDDB_GRID_ID);
    assert_eq!(artwork[0].source(), STEAMGRIDDB_GRID_URL);
    assert_eq!(artwork[0].provider_revision(), 740598);
    assert_eq!(artwork[1].artwork_type(), ArtworkType::Banner);
    assert_eq!(artwork[1].external_asset_id(), "740599");
    assert_eq!(artwork[2].artwork_type(), ArtworkType::Logo);
    assert_eq!(artwork[2].external_asset_id(), "740600");
    assert_eq!(artwork[3].artwork_type(), ArtworkType::Icon);
    assert_eq!(artwork[3].external_asset_id(), "740601");
    assert!(artwork.iter().all(|candidate| {
        candidate.region().is_none()
            && candidate.language().is_none()
            && candidate.width().is_none()
            && candidate.height().is_none()
            && candidate.quality() == 0
            && candidate.discovered_at() == 0
    }));

    let requests = transport.requests();
    assert_eq!(requests.len(), 4);
    for (request, endpoint) in requests.iter().zip(["grids", "heroes", "logos", "icons"]) {
        assert_eq!(request.method(), "GET");
        assert!(request.body().is_empty());
        assert_eq!(
            request.url(),
            format!("https://fixture.invalid/steamgriddb/{endpoint}/game/{STEAMGRIDDB_GAME_ID}")
        );
        assert_eq!(
            request.headers().get("authorization"),
            Some(&"Bearer secret".to_owned())
        );
    }
}

#[test]
fn gametdb_rejects_wrong_or_noncanonical_identifiers() {
    let wrong_identifier = GameTdbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::new(
                200,
                b"TITLES = https://www.gametdb.com (type: DS language: EN version: 4)\nA2DE = Alpha\n".to_vec(),
            )),
        },
        "https://fixture.invalid/gametdb",
    );
    assert_eq!(
        wrong_identifier
            .lookup_exact(PlatformId::NintendoNds, "product:A2DP")
            .expect("response should be well formed"),
        None
    );

    let lowercase_identifier = GameTdbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::new(
                200,
                b"TITLES = https://www.gametdb.com (type: DS language: EN version: 4)\nA2DE = Alpha\n".to_vec(),
            )),
        },
        "https://fixture.invalid/gametdb",
    );
    assert_eq!(
        lowercase_identifier.lookup_exact(PlatformId::NintendoNds, "product:a2de"),
        Err(ProviderAdapterError::InvalidResponse)
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
        "gametdb:A2DE:cover",
        ProviderId::GameTdb,
        "A2DE",
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
fn steamgriddb_rejects_signed_wire_urls_instead_of_retaining_them() {
    let adapter = SteamGridDbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::json(
                200,
                br#"{"success":true,"page":0,"total":1,"limit":50,"data":[{"id":740598,"url":"https://cdn2.steamgriddb.com/grid/fixture.png?signature=secret&expires=10"}]}"#,
            )),
        },
        "https://fixture.invalid/steamgriddb",
    );

    assert_eq!(
        adapter.discover_artwork(STEAMGRIDDB_GAME_ID, b"secret"),
        Err(ProviderAdapterError::InvalidResponse)
    );
}

#[test]
fn steamgriddb_download_resolves_an_opaque_locator_through_the_documented_endpoint() {
    let transport = SequenceTransport::new([
        Ok(steamgriddb_response(
            STEAMGRIDDB_GRID_ID.parse().expect("numeric fixture id"),
            STEAMGRIDDB_GRID_URL,
        )),
        Ok(ProviderResponse::new(200, b"original-image-bytes".to_vec())),
    ]);
    let adapter = SteamGridDbAdapter::new(transport.clone(), "https://fixture.invalid/steamgriddb");

    let bytes = adapter
        .download_artwork(STEAMGRIDDB_GAME_ID, "asset:740598", b"secret")
        .expect("documented discovery should resolve the original URL");

    assert_eq!(bytes, b"original-image-bytes");
    let requests = transport.requests();
    assert_eq!(requests.len(), 2);
    assert_eq!(
        requests[0].url(),
        "https://fixture.invalid/steamgriddb/grids/game/5249689"
    );
    assert_eq!(
        requests[0].headers().get("authorization"),
        Some(&"Bearer secret".to_owned())
    );
    assert_eq!(requests[1].url(), STEAMGRIDDB_GRID_URL);
    assert!(requests[1].headers().is_empty());
    assert!(requests[1].body().is_empty());
}

#[test]
fn steamgriddb_download_accepts_a_valid_credential_free_url_without_auth_header() {
    let transport = SequenceTransport::new([Ok(ProviderResponse::new(
        200,
        b"original-image-bytes".to_vec(),
    ))]);
    let adapter = SteamGridDbAdapter::new(transport.clone(), "https://fixture.invalid/steamgriddb");

    let bytes = adapter
        .download_artwork(STEAMGRIDDB_GAME_ID, STEAMGRIDDB_GRID_URL, b"secret")
        .expect("stable provider URL should download");

    assert_eq!(bytes, b"original-image-bytes");
    let requests = transport.requests();
    assert_eq!(requests.len(), 1);
    assert_eq!(requests[0].url(), STEAMGRIDDB_GRID_URL);
    assert!(requests[0].headers().is_empty());
}

#[test]
fn steamgriddb_empty_endpoint_results_are_supported() {
    let transport = SequenceTransport::new([
        Ok(steamgriddb_empty_response()),
        Ok(steamgriddb_empty_response()),
        Ok(steamgriddb_empty_response()),
        Ok(steamgriddb_empty_response()),
    ]);
    let adapter = SteamGridDbAdapter::new(transport, "https://fixture.invalid/steamgriddb");

    assert!(
        adapter
            .discover_artwork(STEAMGRIDDB_GAME_ID, b"secret")
            .expect("empty v2 responses are valid")
            .is_empty()
    );
}

#[test]
fn steamgriddb_rejects_malformed_oversized_and_unsupported_wire_results() {
    let malformed_id = SteamGridDbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::json(
                200,
                br#"{"success":true,"page":0,"total":1,"limit":50,"data":[{"id":"740598","url":"https://cdn2.steamgriddb.com/grid/fixture.png"}]}"#,
            )),
        },
        "https://fixture.invalid/steamgriddb",
    );
    assert_eq!(
        malformed_id.discover_artwork(STEAMGRIDDB_GAME_ID, b"secret"),
        Err(ProviderAdapterError::InvalidResponse)
    );

    let unsupported_shape = SteamGridDbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::json(
                200,
                br#"{"success":false,"errors":["unsupported"]}"#,
            )),
        },
        "https://fixture.invalid/steamgriddb",
    );
    assert_eq!(
        unsupported_shape.discover_artwork(STEAMGRIDDB_GAME_ID, b"secret"),
        Err(ProviderAdapterError::InvalidResponse)
    );

    let oversized = SteamGridDbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::new(200, vec![b'x'; 2 * 1024 * 1024 + 1])),
        },
        "https://fixture.invalid/steamgriddb",
    );
    assert_eq!(
        oversized.discover_artwork(STEAMGRIDDB_GAME_ID, b"secret"),
        Err(ProviderAdapterError::Transport(
            ProviderTransportError::ResponseTooLarge
        ))
    );
}

#[test]
fn steamgriddb_authentication_and_rate_limits_remain_typed_failures() {
    for (status, expected) in [
        (401, ProviderAdapterError::AuthenticationFailed),
        (403, ProviderAdapterError::AuthenticationFailed),
        (429, ProviderAdapterError::RateLimited),
    ] {
        let adapter = SteamGridDbAdapter::new(
            FixtureTransport {
                response: Ok(ProviderResponse::new(status, b"{}".to_vec())),
            },
            "https://fixture.invalid/steamgriddb",
        );
        assert_eq!(
            adapter.discover_artwork(STEAMGRIDDB_GAME_ID, b"secret"),
            Err(expected),
            "status {status} should retain its typed failure"
        );
    }
}

#[test]
fn steamgriddb_credential_validation_uses_a_documented_read_only_endpoint() {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let validator = SteamGridDbCredentialValidator::new(
        RecordingTransport {
            response: Ok(ProviderResponse::json(
                200,
                br#"{"success":true,"data":[]}"#,
            )),
            requests: Arc::clone(&requests),
        },
        "https://fixture.invalid/steamgriddb",
    );

    assert_eq!(validator.validate(b"secret"), Ok(()));
    let requests = requests.lock().expect("request recorder lock");
    assert_eq!(requests.len(), 1);
    assert_eq!(
        requests[0].url(),
        "https://fixture.invalid/steamgriddb/search/autocomplete/tetris"
    );
    assert_eq!(
        requests[0].headers().get("authorization"),
        Some(&"Bearer secret".to_owned())
    );
    assert!(requests[0].body().is_empty());
}

#[test]
fn steamgriddb_rejects_invalid_game_and_asset_locators_before_transport() {
    let transport = SequenceTransport::new([Ok(ProviderResponse::new(
        200,
        b"original-image-bytes".to_vec(),
    ))]);
    let adapter = SteamGridDbAdapter::new(transport.clone(), "https://fixture.invalid/steamgriddb");

    for (external_game_id, locator) in [
        ("game/escape", "asset:740598"),
        (STEAMGRIDDB_GAME_ID, "asset:../escape"),
        (STEAMGRIDDB_GAME_ID, "asset:unknown:740598"),
        (
            STEAMGRIDDB_GAME_ID,
            "https://cdn2.steamgriddb.com/grid/fixture.png?sig=secret",
        ),
        (
            STEAMGRIDDB_GAME_ID,
            "https://untrusted.example/grid/fixture.png",
        ),
    ] {
        assert_eq!(
            adapter.download_artwork(external_game_id, locator, b"secret"),
            Err(ProviderAdapterError::InvalidResponse),
            "invalid SGDB input should be rejected: {external_game_id} {locator}"
        );
    }
    assert!(transport.requests().is_empty());
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
                PLAYMATCH_SHA256,
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
            response: Ok(ProviderResponse::json(200, PLAYMATCH_V2_RELATIONS)),
        },
        "https://fixture.invalid/playmatch",
    );
    let matches = playmatch
        .match_exact(&target(PLAYMATCH_SHA256))
        .expect("playmatch session response");
    assert_eq!(matches.len(), 1);
    assert_eq!(matches[0].provider_id(), ProviderId::Playmatch);

    let mut gametdb = GameTdbSession::new(
        FixtureTransport {
            response: Ok(ProviderResponse::new(
                200,
                b"TITLES = https://www.gametdb.com (type: DS language: EN version: 4)\nA2DE = Alpha\n".to_vec(),
            )),
        },
        "https://fixture.invalid/gametdb",
    );
    let matches = gametdb
        .match_exact(&target_for(
            PlatformId::NintendoNds,
            "nintendo.nds",
            "product:A2DE",
        ))
        .expect("gametdb session response");
    let metadata = gametdb
        .fetch_metadata(
            &target_for(PlatformId::NintendoNds, "nintendo.nds", "product:A2DE"),
            &ExternalIdentityMapping::new(
                GameContentId::from_bytes([1; 16]).expect("content id"),
                ProviderId::GameTdb,
                "A2DE",
                None,
                "nintendo.nds",
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
        SequenceTransport::new([
            Ok(steamgriddb_response(
                STEAMGRIDDB_GRID_ID.parse().expect("numeric fixture id"),
                STEAMGRIDDB_GRID_URL,
            )),
            Ok(steamgriddb_empty_response()),
            Ok(steamgriddb_empty_response()),
            Ok(steamgriddb_empty_response()),
        ]),
        "https://fixture.invalid/steamgriddb",
        FixtureCredentialStore,
    );
    let references = steamgriddb
        .discover_artwork(&ExternalIdentityMapping::new(
            GameContentId::from_bytes([1; 16]).expect("content id"),
            ProviderId::SteamGridDb,
            STEAMGRIDDB_GAME_ID,
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
    assert_eq!(references[0].source(), STEAMGRIDDB_GRID_URL);
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
        session.match_exact(&target(PLAYMATCH_SHA256)),
        Err(HydrationProviderError::RateLimited)
    );

    let adapter = GameTdbAdapter::new(
        FixtureTransport {
            response: Ok(ProviderResponse::new(200, vec![0_u8; 2 * 1024 * 1024 + 1])),
        },
        "https://fixture.invalid/gametdb",
    );
    assert_eq!(
        adapter.download_artwork("A2DE", "https://fixture.invalid/asset.png"),
        Err(ProviderAdapterError::Transport(
            ProviderTransportError::ResponseTooLarge,
        ))
    );
}

#[test]
fn credential_store_unavailability_stops_credentialed_session_before_transport() {
    let mut session = SteamGridDbSession::new(
        NoNetworkTransport,
        "https://fixture.invalid/steamgriddb",
        UnavailableCredentialStore,
    );
    let mapping = ExternalIdentityMapping::new(
        GameContentId::from_bytes([1; 16]).expect("content id"),
        ProviderId::SteamGridDb,
        "game-1",
        None,
        "gb",
        None,
        MatchBasis::ExistingExactMapping,
        1,
        MappingState::Current,
        100,
        100,
    );

    assert_eq!(
        session.discover_artwork(&mapping),
        Err(HydrationProviderError::Unavailable)
    );
}
