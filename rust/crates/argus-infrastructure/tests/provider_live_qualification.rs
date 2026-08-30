//! Opt-in live qualification for the production enrichment boundary.
//!
//! These tests use only non-secret provider record identifiers supplied by the
//! operator. The production session factory owns transport construction, and
//! the credentialed session reads its secret through the production
//! application credential service. No ROM bytes, credential environment
//! variables, provider responses, or signed URLs are written to qualification
//! output.

use argus_application::{
    ArtworkReference, ArtworkSource, EnrichmentProviderSession, ExactMatchEvidence,
    ExternalIdentityMapping, HydrationProviderError, HydrationTarget, MappingState, MatchBasis,
    MetadataProviderService, ProviderId, ProviderReadinessState,
};
use argus_domain::{GameContentId, GameId, PlatformId};
use argus_infrastructure::credentials::KeyringSecureCredentialStore;
use argus_infrastructure::providers::{
    ProductionProviderSessionFactory, SteamGridDbCredentialValidator, UreqTransport,
};

const STEAMGRIDDB_API_BASE_URL: &str = "https://www.steamgriddb.com/api/v2";
const PLAYMATCH_PROBE_PLATFORM: PlatformId = PlatformId::NintendoGb;
const PLAYMATCH_PROBE_PROVIDER_PLATFORM: &str = "nintendo.gb";
const GAMETDB_PROBE_PLATFORM: PlatformId = PlatformId::NintendoNds;
const GAMETDB_PROBE_PROVIDER_PLATFORM: &str = "nintendo.nds";
const STEAMGRIDDB_PROBE_PLATFORM: PlatformId = PlatformId::NintendoGb;
const STEAMGRIDDB_PROBE_PROVIDER_PLATFORM: &str = STEAMGRIDDB_PROBE_PLATFORM.as_str();

fn probe_game_id() -> GameId {
    GameId::from_bytes([2; 16]).expect("qualification game identity")
}

fn probe_content_id() -> GameContentId {
    GameContentId::from_bytes([1; 16]).expect("qualification content identity")
}

fn safe_probe_value(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 512
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-' | b':'))
}

fn probe_input(name: &str) -> Option<String> {
    std::env::var(name)
        .ok()
        .filter(|value| safe_probe_value(value))
}

fn game_tdb_probe_input(name: &str) -> Option<String> {
    probe_input(name).filter(|value| {
        let Some(raw_identifier) = value
            .strip_prefix("product:")
            .or_else(|| value.strip_prefix("native:"))
        else {
            return false;
        };
        raw_identifier.len() == 4
            && raw_identifier
                .bytes()
                .all(|byte| byte.is_ascii_digit() || byte.is_ascii_uppercase())
    })
}

fn playmatch_probe_input(name: &str) -> Option<String> {
    probe_input(name).filter(|value| {
        value.len() == 64
            && value
                .bytes()
                .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    })
}

fn numeric_probe_input(name: &str) -> Option<String> {
    probe_input(name).filter(|value| value.bytes().all(|byte| byte.is_ascii_digit()))
}

fn target(platform_id: PlatformId, provider_platform_id: &str, identity: &str) -> HydrationTarget {
    HydrationTarget::new(
        probe_game_id(),
        probe_content_id(),
        platform_id,
        identity,
        provider_platform_id,
    )
    .with_observed_at(1)
}

fn production_session(
    sessions: Vec<Box<dyn EnrichmentProviderSession>>,
    provider_id: ProviderId,
) -> Box<dyn EnrichmentProviderSession> {
    sessions
        .into_iter()
        .find(|session| session.provider_id() == provider_id)
        .expect("production provider roster is incomplete")
}

fn print_not_run(provider: &str, platform: &str, reason: &str) {
    println!("LIVE_PROVIDER {provider}: NOT RUN platform={platform} ({reason})");
}

fn live_prerequisite_reason(error: HydrationProviderError) -> Option<&'static str> {
    match error {
        HydrationProviderError::AuthenticationFailed => {
            Some("production provider authentication is unavailable")
        }
        HydrationProviderError::RateLimited => Some("production provider is rate limited"),
        HydrationProviderError::Timeout => Some("production provider request timed out"),
        HydrationProviderError::Unavailable => {
            Some("production provider or network is unavailable")
        }
        HydrationProviderError::AuthorizationFailed
        | HydrationProviderError::Misconfigured
        | HydrationProviderError::InvalidResponse
        | HydrationProviderError::UnsupportedCapability => None,
    }
}

fn live_result_or_not_run<T>(
    provider: &str,
    platform: &str,
    operation: &str,
    result: Result<T, HydrationProviderError>,
) -> Option<T> {
    match result {
        Ok(value) => Some(value),
        Err(error) => {
            if let Some(reason) = live_prerequisite_reason(error) {
                print_not_run(provider, platform, reason);
                None
            } else {
                panic!("production {provider} {operation} failed with {error:?}");
            }
        }
    }
}

#[test]
fn live_transport_prerequisite_errors_are_not_run() {
    for error in [
        HydrationProviderError::AuthenticationFailed,
        HydrationProviderError::RateLimited,
        HydrationProviderError::Timeout,
        HydrationProviderError::Unavailable,
    ] {
        assert!(live_prerequisite_reason(error).is_some());
    }
    assert!(live_prerequisite_reason(HydrationProviderError::InvalidResponse).is_none());
}

#[test]
#[ignore = "requires operator-supplied non-secret probe identifiers and network access"]
fn production_playmatch_live_qualification() {
    let Some(identity) = playmatch_probe_input("ARGUS_LIVE_PLAYMATCH_IDENTITY") else {
        print_not_run(
            "playmatch",
            PLAYMATCH_PROBE_PROVIDER_PLATFORM,
            "missing or invalid non-secret probe input",
        );
        return;
    };
    let Some(expected_external_id) = probe_input("ARGUS_LIVE_PLAYMATCH_EXTERNAL_ID") else {
        print_not_run(
            "playmatch",
            PLAYMATCH_PROBE_PROVIDER_PLATFORM,
            "missing or invalid non-secret probe input",
        );
        return;
    };

    let mut session = production_session(
        ProductionProviderSessionFactory::new().create_sessions(),
        ProviderId::Playmatch,
    );
    let expected_content_id = probe_content_id();
    let Some(matches) = live_result_or_not_run(
        "playmatch",
        PLAYMATCH_PROBE_PROVIDER_PLATFORM,
        "exact match",
        session.match_exact(&target(
            PLAYMATCH_PROBE_PLATFORM,
            PLAYMATCH_PROBE_PROVIDER_PLATFORM,
            &identity,
        )),
    ) else {
        return;
    };
    let has_exact_match = matches.iter().any(|candidate| {
        candidate.provider_id() == ProviderId::Playmatch
            && candidate.external_game_id() == expected_external_id
            && matches!(
                candidate.evidence(),
                ExactMatchEvidence::Playmatch {
                    game_content_id,
                    platform_id,
                    submitted_identity,
                    response_identity,
                    ..
                } if *game_content_id == expected_content_id
                    && *platform_id == PLAYMATCH_PROBE_PLATFORM
                    && submitted_identity == &identity
                    && response_identity == &identity
            )
    });
    assert!(
        has_exact_match,
        "production Playmatch response did not prove the configured exact match"
    );
    println!("LIVE_PROVIDER playmatch: PASS platform={PLAYMATCH_PROBE_PROVIDER_PLATFORM}");
}

#[test]
#[ignore = "requires operator-supplied non-secret probe identifiers and network access"]
fn production_gametdb_live_qualification() {
    let Some(identifier) = game_tdb_probe_input("ARGUS_LIVE_GAMETDB_IDENTIFIER") else {
        print_not_run(
            "gametdb",
            GAMETDB_PROBE_PROVIDER_PLATFORM,
            "missing or invalid non-secret probe input",
        );
        return;
    };
    let Some(expected_external_id) = probe_input("ARGUS_LIVE_GAMETDB_EXTERNAL_ID") else {
        print_not_run(
            "gametdb",
            GAMETDB_PROBE_PROVIDER_PLATFORM,
            "missing or invalid non-secret probe input",
        );
        return;
    };

    let mut session = production_session(
        ProductionProviderSessionFactory::new().create_sessions(),
        ProviderId::GameTdb,
    );
    let expected_content_id = probe_content_id();
    let hydration_target = target(
        GAMETDB_PROBE_PLATFORM,
        GAMETDB_PROBE_PROVIDER_PLATFORM,
        &identifier,
    );
    let Some(matches) = live_result_or_not_run(
        "gametdb",
        GAMETDB_PROBE_PROVIDER_PLATFORM,
        "exact match",
        session.match_exact(&hydration_target),
    ) else {
        return;
    };
    let Some(candidate) = matches.iter().find(|candidate| {
        candidate.provider_id() == ProviderId::GameTdb
            && candidate.external_game_id() == expected_external_id
            && matches!(
                candidate.evidence(),
                ExactMatchEvidence::GameTdb {
                    game_content_id,
                    platform_id,
                    native_identifier,
                    validated_identifier,
                    ..
                } if *game_content_id == expected_content_id
                    && *platform_id == GAMETDB_PROBE_PLATFORM
                    && native_identifier == &identifier
                    && validated_identifier == &identifier
            )
    }) else {
        panic!("production GameTDB response did not prove the configured exact match");
    };

    let mapping = ExternalIdentityMapping::new(
        expected_content_id,
        ProviderId::GameTdb,
        candidate.external_game_id(),
        None,
        GAMETDB_PROBE_PROVIDER_PLATFORM,
        Some(100),
        MatchBasis::GameTdbExactNativeIdentifier,
        1,
        MappingState::Current,
        1,
        1,
    );
    let metadata = match live_result_or_not_run(
        "gametdb",
        GAMETDB_PROBE_PROVIDER_PLATFORM,
        "metadata lookup",
        session.fetch_metadata(&hydration_target, &mapping),
    ) {
        Some(Some(metadata)) => metadata,
        Some(None) => panic!("production GameTDB returned no metadata for the exact mapping"),
        None => return,
    };
    assert_eq!(metadata.provider_id(), ProviderId::GameTdb);
    assert_eq!(metadata.external_game_id(), expected_external_id);
    println!("LIVE_PROVIDER gametdb: PASS platform={GAMETDB_PROBE_PROVIDER_PLATFORM}");
}

#[test]
#[ignore = "requires operator-supplied non-secret probe identifiers, keyring access, and network access"]
fn production_steamgriddb_live_qualification() {
    let Some(expected_external_id) = numeric_probe_input("ARGUS_LIVE_STEAMGRIDDB_EXTERNAL_ID")
    else {
        print_not_run(
            "steamgriddb",
            STEAMGRIDDB_PROBE_PROVIDER_PLATFORM,
            "missing or invalid non-secret probe input",
        );
        return;
    };
    let Some(expected_asset_id) = numeric_probe_input("ARGUS_LIVE_STEAMGRIDDB_ASSET_ID") else {
        print_not_run(
            "steamgriddb",
            STEAMGRIDDB_PROBE_PROVIDER_PLATFORM,
            "missing or invalid non-secret probe input",
        );
        return;
    };

    // This is the same application-owned credential service used by runtime
    // bootstrap. It reports only readiness; the secret remains in the keyring
    // and is borrowed internally by the production session.
    let mut credential_service = MetadataProviderService::new(
        KeyringSecureCredentialStore::new(),
        SteamGridDbCredentialValidator::new(UreqTransport::new(), STEAMGRIDDB_API_BASE_URL),
    );
    let readiness = match credential_service.refresh_readiness_from_store() {
        Ok(readiness) => readiness,
        Err(_) => {
            print_not_run(
                "steamgriddb",
                STEAMGRIDDB_PROBE_PROVIDER_PLATFORM,
                "production credential service is unavailable",
            );
            return;
        }
    };
    if readiness.state() != ProviderReadinessState::Ready {
        print_not_run(
            "steamgriddb",
            STEAMGRIDDB_PROBE_PROVIDER_PLATFORM,
            "production credential service has no usable credential",
        );
        return;
    }

    let mapping = ExternalIdentityMapping::new(
        probe_content_id(),
        ProviderId::SteamGridDb,
        expected_external_id.clone(),
        None,
        STEAMGRIDDB_PROBE_PROVIDER_PLATFORM,
        None,
        MatchBasis::ExistingExactMapping,
        1,
        MappingState::Current,
        1,
        1,
    );
    let mut session = production_session(
        ProductionProviderSessionFactory::new().create_sessions(),
        ProviderId::SteamGridDb,
    );
    let Some(artwork) = live_result_or_not_run(
        "steamgriddb",
        STEAMGRIDDB_PROBE_PROVIDER_PLATFORM,
        "artwork discovery",
        session.discover_artwork(&mapping),
    ) else {
        return;
    };
    let Some(candidate) = artwork.iter().find(|candidate| {
        candidate.provider_id() == ProviderId::SteamGridDb
            && candidate.external_asset_id() == expected_asset_id
    }) else {
        panic!("production SteamGridDB response did not prove the configured artwork asset");
    };
    assert!(
        candidate.source().starts_with("https://") && !candidate.source().contains(['?', '#', '@']),
        "production SteamGridDB response did not provide a stable credential-free source"
    );
    let reference = ArtworkReference::new(
        format!("steamgriddb:{expected_external_id}:{expected_asset_id}"),
        ProviderId::SteamGridDb,
        expected_external_id,
        candidate.artwork_type(),
        ArtworkSource::CredentialFreeUrl(candidate.source().to_owned()),
        candidate.width(),
        candidate.height(),
        None,
        None,
        candidate.region().map(str::to_owned),
        candidate.language().map(str::to_owned),
        candidate.provider_revision(),
    )
    .with_quality(candidate.quality())
    .with_discovered_at(candidate.discovered_at());
    let Some(bytes) = live_result_or_not_run(
        "steamgriddb",
        STEAMGRIDDB_PROBE_PROVIDER_PLATFORM,
        "artwork download",
        session.download_artwork(&reference),
    ) else {
        return;
    };
    assert!(
        !bytes.is_empty(),
        "production SteamGridDB returned no original artwork bytes"
    );
    println!("LIVE_PROVIDER steamgriddb: PASS platform={STEAMGRIDDB_PROBE_PROVIDER_PLATFORM}");
}

#[test]
fn live_probe_input_names_do_not_include_credential_material() {
    for name in [
        "ARGUS_LIVE_PLAYMATCH_IDENTITY",
        "ARGUS_LIVE_PLAYMATCH_EXTERNAL_ID",
        "ARGUS_LIVE_GAMETDB_IDENTIFIER",
        "ARGUS_LIVE_GAMETDB_EXTERNAL_ID",
        "ARGUS_LIVE_STEAMGRIDDB_EXTERNAL_ID",
        "ARGUS_LIVE_STEAMGRIDDB_ASSET_ID",
    ] {
        assert!(!name.contains("SECRET"));
        assert!(!name.contains("TOKEN"));
        assert!(!name.contains("KEY"));
    }
}
