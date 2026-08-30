//! Production-provider transport and normalization adapters.
//!
//! Adapters own request formation and response parsing. Application policy only
//! consumes the normalized provider-neutral values returned from this module.

use std::collections::BTreeMap;
use std::fmt;
use std::net::ToSocketAddrs;
use std::time::Duration;

use argus_application::{
    ArtworkCandidate, ArtworkType, CredentialValidationError, CredentialValidator,
    EnrichmentProviderSession, ExactMatchEvidence, ExternalIdentityMapping,
    HydrationMappingCandidate, HydrationProviderError, HydrationTarget, ProviderId,
    ProviderMetadata, SecureCredentialStore,
};
use argus_domain::{GameContentId, PlatformId};
use serde_json::Value;

use crate::credentials::KeyringSecureCredentialStore;

const MAX_PROVIDER_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const MAX_PROVIDER_ATTEMPTS: usize = 3;
const PLAYMATCH_PROBE_FILE_NAME: &str = "argus-probe.rom";
const PLAYMATCH_PROBE_FILE_SIZE: u64 = 0;
const GAMETDB_DS_CATALOG_PATH: &str = "/dstdb.txt?LANG=EN";
const GAMETDB_ARTWORK_BASE_URL: &str = "https://art.gametdb.com";
const STEAMGRIDDB_CREDENTIAL_VALIDATION_TERM: &str = "tetris";
const MAX_GAMETDB_CATALOG_LINE_BYTES: usize = 4096;
const MAX_GAMETDB_TITLE_BYTES: usize = 2048;

/// One bounded synchronous provider request.
#[derive(Clone, Eq, PartialEq)]
pub struct ProviderRequest {
    method: String,
    url: String,
    headers: BTreeMap<String, String>,
    body: Vec<u8>,
}

impl fmt::Debug for ProviderRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let headers = self
            .headers
            .keys()
            .map(|key| (key, "<redacted>"))
            .collect::<BTreeMap<_, _>>();
        formatter
            .debug_struct("ProviderRequest")
            .field("method", &self.method)
            .field("url", &redact_url(&self.url))
            .field("headers", &headers)
            .field("body_len", &self.body.len())
            .finish()
    }
}

impl ProviderRequest {
    /// Creates a request with an already bounded body.
    pub fn new(
        method: impl Into<String>,
        url: impl Into<String>,
        headers: BTreeMap<String, String>,
        body: impl Into<Vec<u8>>,
    ) -> Self {
        Self {
            method: method.into(),
            url: url.into(),
            headers,
            body: body.into(),
        }
    }

    /// Returns the HTTP method.
    pub fn method(&self) -> &str {
        &self.method
    }

    /// Returns the request URL.
    pub fn url(&self) -> &str {
        &self.url
    }

    /// Returns headers without special transport objects.
    pub fn headers(&self) -> &BTreeMap<String, String> {
        &self.headers
    }

    /// Returns the request body.
    pub fn body(&self) -> &[u8] {
        &self.body
    }
}

/// One bounded transport response.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProviderResponse {
    status: u16,
    body: Vec<u8>,
}

impl ProviderResponse {
    /// Creates a response fixture.
    pub fn new(status: u16, body: impl Into<Vec<u8>>) -> Self {
        Self {
            status,
            body: body.into(),
        }
    }

    /// Creates a JSON response fixture.
    pub fn json(status: u16, body: &[u8]) -> Self {
        Self::new(status, body.to_vec())
    }

    /// Returns the status code.
    pub const fn status(&self) -> u16 {
        self.status
    }

    /// Returns bounded response bytes.
    pub fn body(&self) -> &[u8] {
        &self.body
    }
}

/// Transport-level failures normalized before application policy sees them.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ProviderTransportError {
    /// The request exceeded its bounded time budget.
    Timeout,
    /// The provider or network was unavailable.
    Unavailable,
    /// The response exceeded the configured byte budget.
    ResponseTooLarge,
    /// The provider returned a rate-limit response.
    RateLimited,
    /// The provider returned an authentication failure.
    AuthenticationFailed,
}

/// Synchronous transport seam used by every provider adapter.
pub trait ProviderTransport: Clone + Send + Sync + 'static {
    /// Sends one request on the caller's backend worker context.
    fn send(&self, request: ProviderRequest) -> Result<ProviderResponse, ProviderTransportError>;
}

/// Bounded synchronous `ureq` transport used by production provider sessions.
#[derive(Clone)]
pub struct UreqTransport {
    agent: ureq::Agent,
    max_response_bytes: usize,
}

impl UreqTransport {
    /// Maximum provider response body accepted by adapters.
    pub const DEFAULT_MAX_RESPONSE_BYTES: usize = 2 * 1024 * 1024;

    /// Creates a transport with fixed timeout, strict redirect, and body limits.
    pub fn new() -> Self {
        let config = ureq::Agent::config_builder()
            .timeout_global(Some(Duration::from_secs(15)))
            // Redirect destinations are provider-controlled input. Denying
            // redirects keeps URL validation effective for every request and
            // avoids turning a provider response into an SSRF primitive.
            .max_redirects(0)
            .build();
        Self {
            agent: ureq::Agent::new_with_config(config),
            max_response_bytes: Self::DEFAULT_MAX_RESPONSE_BYTES,
        }
    }
}

impl Default for UreqTransport {
    fn default() -> Self {
        Self::new()
    }
}

impl ProviderTransport for UreqTransport {
    fn send(&self, request: ProviderRequest) -> Result<ProviderResponse, ProviderTransportError> {
        for attempt in 0..MAX_PROVIDER_ATTEMPTS {
            match self.send_once(request.clone()) {
                Err(error)
                    if retryable_transport_error(&error) && attempt + 1 < MAX_PROVIDER_ATTEMPTS =>
                {
                    std::thread::sleep(Duration::from_millis(25 * (1_u64 << attempt)));
                }
                result => return result,
            }
        }
        unreachable!("bounded provider attempts always return")
    }
}

impl UreqTransport {
    fn send_once(
        &self,
        request: ProviderRequest,
    ) -> Result<ProviderResponse, ProviderTransportError> {
        let ProviderRequest {
            method,
            url,
            headers,
            body,
        } = request;
        if !is_allowed_transport_url(&url) {
            return Err(ProviderTransportError::Unavailable);
        }
        let response = if method.eq_ignore_ascii_case("GET") {
            let mut builder = self.agent.get(&url);
            for (key, value) in headers {
                builder = builder.header(key, value);
            }
            builder.call()
        } else if method.eq_ignore_ascii_case("POST") {
            let mut builder = self.agent.post(&url);
            for (key, value) in headers {
                builder = builder.header(key, value);
            }
            builder.send(body)
        } else {
            return Err(ProviderTransportError::Unavailable);
        }
        .map_err(|error| match error {
            ureq::Error::StatusCode(401 | 403) => ProviderTransportError::AuthenticationFailed,
            ureq::Error::StatusCode(429) => ProviderTransportError::RateLimited,
            ureq::Error::StatusCode(408 | 504) => ProviderTransportError::Timeout,
            ureq::Error::StatusCode(_) => ProviderTransportError::Unavailable,
            ureq::Error::Timeout(_) => ProviderTransportError::Timeout,
            _ => ProviderTransportError::Unavailable,
        })?;
        let status = response.status().as_u16();
        if status == 401 || status == 403 {
            return Err(ProviderTransportError::AuthenticationFailed);
        }
        if status == 429 {
            return Err(ProviderTransportError::RateLimited);
        }
        let body = read_bounded_body(response.into_body(), self.max_response_bytes)?;
        Ok(ProviderResponse::new(status, body))
    }
}

/// Adapter-level failures after transport normalization.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ProviderAdapterError {
    /// A lower-level transport failure.
    Transport(ProviderTransportError),
    /// The provider rejected the supplied authentication.
    AuthenticationFailed,
    /// The provider requested rate limiting.
    RateLimited,
    /// The response status or schema was not accepted.
    InvalidResponse,
    /// The provider does not support this platform/evidence form.
    UnsupportedCapability,
}

/// Playmatch exact-content adapter.
#[derive(Clone)]
pub struct PlaymatchAdapter<T> {
    transport: T,
    base_url: String,
}

impl<T> PlaymatchAdapter<T>
where
    T: ProviderTransport,
{
    /// Creates an adapter with an explicit base endpoint.
    pub fn new(transport: T, base_url: impl Into<String>) -> Self {
        Self {
            transport,
            base_url: base_url.into(),
        }
    }

    /// Requests exact evidence for one canonical content identity.
    pub fn match_exact(
        &self,
        game_content_id: GameContentId,
        platform_id: PlatformId,
        identity: &str,
    ) -> Result<Vec<ExactMatchEvidence>, ProviderAdapterError> {
        if !is_valid_playmatch_sha256(identity) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let Some(provider_platform_name) = playmatch_platform_name(platform_id) else {
            return Err(ProviderAdapterError::UnsupportedCapability);
        };
        // The v2 API gives SHA-256 precedence over filename and size. The
        // application port carries the canonical digest but not a ROM
        // filename or length, so these fixed non-content values deliberately
        // prevent the fallback branch from becoming a fuzzy lookup.
        let url = format!(
            "{}/identify/relations?fileName={PLAYMATCH_PROBE_FILE_NAME}&fileSize={PLAYMATCH_PROBE_FILE_SIZE}&sha256={identity}",
            self.base_url.trim_end_matches('/')
        );
        let response = self.send_get(url)?;
        let root = parse_json(&response)?;
        parse_playmatch_relations(
            &root,
            game_content_id,
            platform_id,
            identity,
            provider_platform_name,
        )
    }

    fn send_get(&self, url: String) -> Result<ProviderResponse, ProviderAdapterError> {
        if !is_provider_url_allowed(&url, ProviderId::Playmatch, true) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let response = self
            .transport
            .send(ProviderRequest::new(
                "GET",
                url,
                BTreeMap::new(),
                Vec::new(),
            ))
            .map_err(map_transport_error)?;
        if response.status() != 200 {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        Ok(response)
    }
}

/// GameTDB exact identifier and metadata adapter.
#[derive(Clone)]
pub struct GameTdbAdapter<T> {
    transport: T,
    base_url: String,
}

impl<T> GameTdbAdapter<T>
where
    T: ProviderTransport,
{
    /// Creates an adapter with an explicit base endpoint.
    pub fn new(transport: T, base_url: impl Into<String>) -> Self {
        Self {
            transport,
            base_url: base_url.into(),
        }
    }

    /// Looks up one exact provider-native identifier.
    pub fn lookup_exact(
        &self,
        platform_id: PlatformId,
        native_identifier: &str,
    ) -> Result<Option<ProviderMetadata>, ProviderAdapterError> {
        if !is_valid_gametdb_identifier(native_identifier) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        if platform_id != PlatformId::NintendoNds {
            return Err(ProviderAdapterError::UnsupportedCapability);
        }
        let requested_id = gametdb_raw_identifier(native_identifier)
            .ok_or(ProviderAdapterError::InvalidResponse)?;
        let url = format!(
            "{}{}",
            self.base_url.trim_end_matches('/'),
            GAMETDB_DS_CATALOG_PATH
        );
        if !is_provider_url_allowed(&url, ProviderId::GameTdb, true) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let response = self
            .transport
            .send(ProviderRequest::new(
                "GET",
                url,
                BTreeMap::new(),
                Vec::new(),
            ))
            .map_err(map_transport_error)?;
        if response.status() != 200 {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let catalog = parse_gametdb_ds_catalog(&response)?;
        let Some(title) = catalog.records.get(requested_id) else {
            return Ok(None);
        };
        Ok(Some(ProviderMetadata::new(
            ProviderId::GameTdb,
            requested_id,
            catalog.revision,
            None,
            Some("en".to_owned()),
            0,
            None,
            Some(title.clone()),
            Vec::new(),
            None,
            None,
            Vec::new(),
            Vec::new(),
            Vec::new(),
            vec!["en".to_owned()],
            100,
            format!("gametdb:{requested_id}"),
        )))
    }

    /// Discovers one official front-cover asset for a known DS identifier.
    pub fn discover_artwork(
        &self,
        external_game_id: &str,
    ) -> Result<Vec<ArtworkCandidate>, ProviderAdapterError> {
        if !is_valid_gametdb_raw_identifier(external_game_id) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let Some(locale) = gametdb_artwork_locale(external_game_id) else {
            return Ok(Vec::new());
        };
        let asset_id = format!("cover:{locale}:{external_game_id}");
        Ok(vec![
            ArtworkCandidate::new(
                ProviderId::GameTdb,
                asset_id.clone(),
                ArtworkType::CoverFront,
                format!("asset:{asset_id}"),
                1,
            )
            .with_details(Some(locale), Some("en"), None, None, 100),
        ])
    }

    /// Downloads original bytes from an official GameTDB asset locator or a
    /// previously persisted provider-owned HTTPS source.
    pub fn download_artwork(
        &self,
        external_game_id: &str,
        source: &str,
    ) -> Result<Vec<u8>, ProviderAdapterError> {
        if !is_valid_gametdb_raw_identifier(external_game_id) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let url = if is_provider_artwork_url_allowed(source, ProviderId::GameTdb, &self.base_url) {
            source.to_owned()
        } else if let Some((locale, asset_game_id)) = gametdb_artwork_locator(source) {
            if asset_game_id != external_game_id {
                return Err(ProviderAdapterError::InvalidResponse);
            }
            let url =
                format!("{GAMETDB_ARTWORK_BASE_URL}/ds/cover/{locale}/{external_game_id}.jpg");
            if !is_provider_url_allowed(&url, ProviderId::GameTdb, false) {
                return Err(ProviderAdapterError::InvalidResponse);
            }
            url
        } else {
            return Err(ProviderAdapterError::InvalidResponse);
        };
        let response = self
            .transport
            .send(ProviderRequest::new(
                "GET",
                url,
                BTreeMap::new(),
                Vec::new(),
            ))
            .map_err(map_transport_error)?;
        if response.status() != 200 {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        bounded_response_body(&response)
    }
}

/// SteamGridDB artwork-only adapter.
#[derive(Clone)]
pub struct SteamGridDbAdapter<T> {
    transport: T,
    base_url: String,
}

#[derive(Clone, Copy)]
enum SteamGridDbAssetKind {
    Grid,
    Hero,
    Logo,
    Icon,
}

const STEAMGRIDDB_ASSET_KINDS: &[SteamGridDbAssetKind] = &[
    SteamGridDbAssetKind::Grid,
    SteamGridDbAssetKind::Hero,
    SteamGridDbAssetKind::Logo,
    SteamGridDbAssetKind::Icon,
];

impl SteamGridDbAssetKind {
    const fn endpoint(self) -> &'static str {
        match self {
            Self::Grid => "grids",
            Self::Hero => "heroes",
            Self::Logo => "logos",
            Self::Icon => "icons",
        }
    }

    const fn artwork_type(self) -> ArtworkType {
        match self {
            Self::Grid => ArtworkType::CoverFront,
            Self::Hero => ArtworkType::Banner,
            Self::Logo => ArtworkType::Logo,
            Self::Icon => ArtworkType::Icon,
        }
    }

    fn from_locator(value: &str) -> Option<Self> {
        match value {
            "grid" => Some(Self::Grid),
            "hero" => Some(Self::Hero),
            "logo" => Some(Self::Logo),
            "icon" => Some(Self::Icon),
            _ => None,
        }
    }
}

struct SteamGridDbAsset {
    id: u64,
    source_url: String,
}

impl<T> SteamGridDbAdapter<T>
where
    T: ProviderTransport,
{
    /// Creates an adapter with an explicit base endpoint.
    pub fn new(transport: T, base_url: impl Into<String>) -> Self {
        Self {
            transport,
            base_url: base_url.into(),
        }
    }

    /// Discovers artwork using an in-memory credential held by the session.
    pub fn discover_artwork(
        &self,
        external_game_id: &str,
        secret: &[u8],
    ) -> Result<Vec<ArtworkCandidate>, ProviderAdapterError> {
        if secret.is_empty() {
            return Err(ProviderAdapterError::UnsupportedCapability);
        }
        if !is_valid_steamgriddb_id(external_game_id) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let token =
            std::str::from_utf8(secret).map_err(|_| ProviderAdapterError::UnsupportedCapability)?;
        let mut candidates = Vec::new();
        for &kind in STEAMGRIDDB_ASSET_KINDS {
            for asset in self.fetch_assets(external_game_id, kind, token)? {
                candidates.push(ArtworkCandidate::new(
                    ProviderId::SteamGridDb,
                    asset.id.to_string(),
                    kind.artwork_type(),
                    asset.source_url,
                    asset.id,
                ));
            }
        }
        Ok(candidates)
    }

    /// Downloads original bytes from a stable provider URL or resolves an
    /// opaque provider asset identity through the documented v2 endpoint.
    pub fn download_artwork(
        &self,
        external_game_id: &str,
        asset_locator: &str,
        secret: &[u8],
    ) -> Result<Vec<u8>, ProviderAdapterError> {
        if secret.is_empty() {
            return Err(ProviderAdapterError::UnsupportedCapability);
        }
        let token =
            std::str::from_utf8(secret).map_err(|_| ProviderAdapterError::UnsupportedCapability)?;
        if !is_valid_steamgriddb_id(external_game_id) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        if is_provider_artwork_url_allowed(asset_locator, ProviderId::SteamGridDb, &self.base_url) {
            return self.download_original_url(asset_locator);
        }

        let (requested_kind, asset_id) = steamgriddb_artwork_locator(asset_locator)
            .ok_or(ProviderAdapterError::InvalidResponse)?;
        let kinds = requested_kind
            .map(|kind| vec![kind])
            .unwrap_or_else(|| STEAMGRIDDB_ASSET_KINDS.to_vec());
        for kind in kinds {
            let assets = self.fetch_assets(external_game_id, kind, token)?;
            if let Some(asset) = assets.into_iter().find(|asset| asset.id == asset_id) {
                return self.download_original_url(&asset.source_url);
            }
        }
        Err(ProviderAdapterError::InvalidResponse)
    }

    fn fetch_assets(
        &self,
        external_game_id: &str,
        kind: SteamGridDbAssetKind,
        token: &str,
    ) -> Result<Vec<SteamGridDbAsset>, ProviderAdapterError> {
        let url = format!(
            "{}/{}/game/{external_game_id}",
            self.base_url.trim_end_matches('/'),
            kind.endpoint()
        );
        if !is_provider_url_allowed(&url, ProviderId::SteamGridDb, false) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let mut headers = BTreeMap::new();
        headers.insert("authorization".to_owned(), format!("Bearer {token}"));
        let response = self
            .transport
            .send(ProviderRequest::new("GET", url, headers, Vec::new()))
            .map_err(map_transport_error)?;
        let response = steamgriddb_success_response(response)?;
        let root = parse_json(&response)?;
        parse_steamgriddb_assets(&root, &self.base_url)
    }

    fn download_original_url(&self, source_url: &str) -> Result<Vec<u8>, ProviderAdapterError> {
        if !is_provider_artwork_url_allowed(source_url, ProviderId::SteamGridDb, &self.base_url) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let response = self
            .transport
            .send(ProviderRequest::new(
                "GET",
                source_url,
                BTreeMap::new(),
                Vec::new(),
            ))
            .map_err(map_transport_error)?;
        let response = steamgriddb_success_response(response)?;
        bounded_response_body(&response)
    }
}

/// Job/operation-scoped Playmatch session over one bounded transport client.
pub struct PlaymatchSession<T> {
    adapter: PlaymatchAdapter<T>,
}

impl<T> PlaymatchSession<T>
where
    T: ProviderTransport,
{
    /// Creates a Playmatch session; the adapter and transport are not shared
    /// application state.
    pub fn new(transport: T, base_url: impl Into<String>) -> Self {
        Self {
            adapter: PlaymatchAdapter::new(transport, base_url),
        }
    }
}

impl<T> EnrichmentProviderSession for PlaymatchSession<T>
where
    T: ProviderTransport,
{
    fn provider_id(&self) -> ProviderId {
        ProviderId::Playmatch
    }

    fn match_exact(
        &mut self,
        target: &HydrationTarget,
    ) -> Result<Vec<HydrationMappingCandidate>, HydrationProviderError> {
        self.adapter
            .match_exact(
                target.game_content_id(),
                target.platform_id(),
                target.submitted_identity(),
            )
            .map_err(map_hydration_error)
            .map(|evidence| {
                evidence
                    .into_iter()
                    .filter_map(|evidence| match &evidence {
                        ExactMatchEvidence::Playmatch {
                            external_game_id, ..
                        } => Some(HydrationMappingCandidate::new(
                            target.game_content_id(),
                            ProviderId::Playmatch,
                            external_game_id.clone(),
                            None,
                            target.provider_platform_id().to_owned(),
                            None,
                            evidence,
                            1,
                            target.observed_at(),
                        )),
                        _ => None,
                    })
                    .collect()
            })
    }
}

/// Job/operation-scoped GameTDB session for exact metadata/artwork refresh.
pub struct GameTdbSession<T> {
    adapter: GameTdbAdapter<T>,
}

impl<T> GameTdbSession<T>
where
    T: ProviderTransport,
{
    /// Creates a GameTDB session over one bounded transport client.
    pub fn new(transport: T, base_url: impl Into<String>) -> Self {
        Self {
            adapter: GameTdbAdapter::new(transport, base_url),
        }
    }
}

impl<T> EnrichmentProviderSession for GameTdbSession<T>
where
    T: ProviderTransport,
{
    fn provider_id(&self) -> ProviderId {
        ProviderId::GameTdb
    }

    fn match_exact(
        &mut self,
        target: &HydrationTarget,
    ) -> Result<Vec<HydrationMappingCandidate>, HydrationProviderError> {
        if !is_valid_gametdb_identifier(target.submitted_identity()) {
            return Ok(Vec::new());
        }
        self.adapter
            .lookup_exact(target.platform_id(), target.submitted_identity())
            .map_err(map_hydration_error)
            .map(|metadata| {
                metadata
                    .map(|metadata| {
                        vec![HydrationMappingCandidate::new(
                            target.game_content_id(),
                            ProviderId::GameTdb,
                            metadata.external_game_id().to_owned(),
                            None,
                            target.provider_platform_id().to_owned(),
                            Some(100),
                            ExactMatchEvidence::GameTdb {
                                game_content_id: target.game_content_id(),
                                platform_id: target.platform_id(),
                                external_game_id: metadata.external_game_id().to_owned(),
                                native_identifier: target.submitted_identity().to_owned(),
                                validated_identifier: target.submitted_identity().to_owned(),
                            },
                            metadata.provider_revision(),
                            target.observed_at(),
                        )]
                    })
                    .unwrap_or_default()
            })
    }

    fn fetch_metadata(
        &mut self,
        target: &HydrationTarget,
        mapping: &ExternalIdentityMapping,
    ) -> Result<Option<ProviderMetadata>, HydrationProviderError> {
        self.adapter
            .lookup_exact(target.platform_id(), target.submitted_identity())
            .map_err(map_hydration_error)
            .and_then(|metadata| {
                if metadata
                    .as_ref()
                    .is_some_and(|value| value.external_game_id() != mapping.external_game_id())
                {
                    return Err(HydrationProviderError::InvalidResponse);
                }
                Ok(metadata)
            })
    }

    fn discover_artwork(
        &mut self,
        mapping: &ExternalIdentityMapping,
    ) -> Result<Vec<ArtworkCandidate>, HydrationProviderError> {
        self.adapter
            .discover_artwork(mapping.external_game_id())
            .map_err(map_hydration_error)
    }

    fn download_artwork(
        &mut self,
        reference: &argus_application::ArtworkReference,
    ) -> Result<Vec<u8>, HydrationProviderError> {
        self.adapter
            .download_artwork(
                reference.external_game_id(),
                reference.source().kind_and_value().1,
            )
            .map_err(map_hydration_error)
    }
}

/// Job/operation-scoped SteamGridDB session with secure-store-owned secret
/// access. The session never exposes the secret outside one adapter callback.
pub struct SteamGridDbSession<T, S> {
    adapter: SteamGridDbAdapter<T>,
    credentials: S,
}

impl<T, S> SteamGridDbSession<T, S>
where
    T: ProviderTransport,
    S: SecureCredentialStore,
{
    /// Creates a credentialed artwork session.
    pub fn new(transport: T, base_url: impl Into<String>, credentials: S) -> Self {
        Self {
            adapter: SteamGridDbAdapter::new(transport, base_url),
            credentials,
        }
    }
}

impl<T, S> EnrichmentProviderSession for SteamGridDbSession<T, S>
where
    T: ProviderTransport,
    S: SecureCredentialStore,
{
    fn provider_id(&self) -> ProviderId {
        ProviderId::SteamGridDb
    }

    fn discover_artwork(
        &mut self,
        mapping: &ExternalIdentityMapping,
    ) -> Result<Vec<ArtworkCandidate>, HydrationProviderError> {
        let mut operation = |secret: &[u8]| {
            self.adapter
                .discover_artwork(mapping.external_game_id(), secret)
                .map_err(map_hydration_error)
        };
        self.credentials
            .with_secret(ProviderId::SteamGridDb, &mut operation)
            .map_err(|_| HydrationProviderError::Unavailable)?
    }

    fn download_artwork(
        &mut self,
        reference: &argus_application::ArtworkReference,
    ) -> Result<Vec<u8>, HydrationProviderError> {
        let locator = reference.source().kind_and_value().1;
        let mut operation = |secret: &[u8]| {
            self.adapter
                .download_artwork(reference.external_game_id(), locator, secret)
                .map_err(map_hydration_error)
        };
        self.credentials
            .with_secret(ProviderId::SteamGridDb, &mut operation)
            .map_err(|_| HydrationProviderError::Unavailable)?
    }
}

fn playmatch_platform_name(platform_id: PlatformId) -> Option<&'static str> {
    match platform_id {
        PlatformId::NintendoGb => Some("Game Boy"),
        _ => None,
    }
}

fn parse_playmatch_relations(
    root: &Value,
    game_content_id: GameContentId,
    platform_id: PlatformId,
    identity: &str,
    provider_platform_name: &str,
) -> Result<Vec<ExactMatchEvidence>, ProviderAdapterError> {
    let match_type = root
        .get("gameMatchType")
        .and_then(Value::as_str)
        .ok_or(ProviderAdapterError::InvalidResponse)?;
    if match_type == "NoMatch" {
        return Ok(Vec::new());
    }
    if !matches!(
        match_type,
        "SHA256" | "SHA1" | "MD5" | "CRC" | "FileNameAndSize"
    ) {
        return Err(ProviderAdapterError::InvalidResponse);
    }
    // The request supplies a SHA-256 identity. A fallback match would be a
    // filename/size guess and therefore cannot become exact application
    // evidence.
    if match_type != "SHA256" {
        return Ok(Vec::new());
    }

    let mut relations = vec![root];
    if let Some(additional_matches) = root.get("additionalMatches")
        && !additional_matches.is_null()
    {
        let additional_matches = additional_matches
            .as_array()
            .ok_or(ProviderAdapterError::InvalidResponse)?;
        relations.extend(additional_matches);
    }

    relations
        .into_iter()
        .map(|relation| {
            let Some((external_game_id, response_identity, response_platform)) =
                playmatch_relation_identity(relation, identity)?
            else {
                return Ok(None);
            };
            if response_platform != provider_platform_name {
                return Ok(None);
            }
            Ok(Some(ExactMatchEvidence::Playmatch {
                game_content_id,
                platform_id,
                external_game_id,
                submitted_identity: identity.to_owned(),
                response_identity,
            }))
        })
        .collect::<Result<Vec<_>, ProviderAdapterError>>()
        .map(|matches| matches.into_iter().flatten().collect())
}

fn playmatch_relation_identity(
    relation: &Value,
    identity: &str,
) -> Result<Option<(String, String, String)>, ProviderAdapterError> {
    let game = relation
        .get("game")
        .and_then(Value::as_object)
        .ok_or(ProviderAdapterError::InvalidResponse)?;
    let external_game_id = game
        .get("id")
        .and_then(Value::as_str)
        .filter(|value| is_valid_external_id(value))
        .ok_or(ProviderAdapterError::InvalidResponse)?;
    let platform = relation
        .get("platform")
        .and_then(Value::as_object)
        .and_then(|platform| platform.get("name"))
        .and_then(Value::as_str)
        .filter(|value| is_valid_provider_label(value))
        .ok_or(ProviderAdapterError::InvalidResponse)?;
    let game_files = relation
        .get("gameFiles")
        .and_then(Value::as_array)
        .ok_or(ProviderAdapterError::InvalidResponse)?;
    let matching_file = game_files.iter().find(|game_file| {
        game_file
            .get("gameId")
            .and_then(Value::as_str)
            .is_some_and(|game_id| game_id == external_game_id)
            && game_file
                .get("sha256")
                .and_then(Value::as_str)
                .is_some_and(|sha256| sha256 == identity)
    });
    let Some(matching_file) = matching_file else {
        return Err(ProviderAdapterError::InvalidResponse);
    };
    let response_identity = matching_file
        .get("sha256")
        .and_then(Value::as_str)
        .filter(|value| is_valid_playmatch_sha256(value))
        .ok_or(ProviderAdapterError::InvalidResponse)?;
    Ok(Some((
        external_game_id.to_owned(),
        response_identity.to_owned(),
        platform.to_owned(),
    )))
}

struct GameTdbDsCatalog {
    revision: u64,
    records: BTreeMap<String, String>,
}

fn parse_gametdb_ds_catalog(
    response: &ProviderResponse,
) -> Result<GameTdbDsCatalog, ProviderAdapterError> {
    let body = bounded_response_body(response)?;
    let text = std::str::from_utf8(&body).map_err(|_| ProviderAdapterError::InvalidResponse)?;
    let mut lines = text.lines();
    let header = lines.next().ok_or(ProviderAdapterError::InvalidResponse)?;
    let revision = parse_gametdb_ds_revision(header)?;
    let mut records = BTreeMap::new();

    for line in lines {
        if line.is_empty() {
            continue;
        }
        if line.len() > MAX_GAMETDB_CATALOG_LINE_BYTES {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let (raw_id, title) = line
            .split_once(" = ")
            .ok_or(ProviderAdapterError::InvalidResponse)?;
        let title = title.trim_end_matches([' ', '\t']);
        if !is_valid_gametdb_raw_identifier(raw_id)
            || title.is_empty()
            || title.len() > MAX_GAMETDB_TITLE_BYTES
            || title.chars().any(char::is_control)
        {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        if records
            .insert(raw_id.to_owned(), title.to_owned())
            .is_some()
        {
            return Err(ProviderAdapterError::InvalidResponse);
        }
    }

    Ok(GameTdbDsCatalog { revision, records })
}

fn parse_gametdb_ds_revision(header: &str) -> Result<u64, ProviderAdapterError> {
    const HEADER_PREFIX: &str = "TITLES = https://www.gametdb.com (type: DS language: EN version: ";
    let version = header
        .strip_prefix(HEADER_PREFIX)
        .and_then(|value| value.strip_suffix(')'))
        .ok_or(ProviderAdapterError::InvalidResponse)?;
    version
        .parse::<u64>()
        .map_err(|_| ProviderAdapterError::InvalidResponse)
}

fn gametdb_raw_identifier(value: &str) -> Option<&str> {
    let raw_identifier = value
        .strip_prefix("product:")
        .or_else(|| value.strip_prefix("native:"))?;
    is_valid_gametdb_raw_identifier(raw_identifier).then_some(raw_identifier)
}

fn is_valid_gametdb_raw_identifier(value: &str) -> bool {
    value.len() == 4
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || byte.is_ascii_uppercase())
}

fn gametdb_artwork_locale(external_game_id: &str) -> Option<&'static str> {
    match external_game_id.as_bytes().last().copied() {
        Some(b'E') => Some("US"),
        Some(b'P') => Some("EN"),
        Some(b'J') => Some("JA"),
        Some(b'K') => Some("KO"),
        _ => None,
    }
}

fn gametdb_artwork_locator(source: &str) -> Option<(&str, &str)> {
    if !is_valid_opaque_locator(source) {
        return None;
    }
    let mut parts = source.strip_prefix("asset:")?.split(':');
    if parts.next()? != "cover" {
        return None;
    }
    let locale = parts.next()?;
    let external_game_id = parts.next()?;
    if parts.next().is_some()
        || gametdb_artwork_locale(external_game_id) != Some(locale)
        || !is_valid_gametdb_raw_identifier(external_game_id)
    {
        return None;
    }
    Some((locale, external_game_id))
}

fn is_valid_playmatch_sha256(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn is_valid_provider_label(value: &str) -> bool {
    !value.is_empty() && value.len() <= 256 && !value.chars().any(char::is_control)
}

fn steamgriddb_artwork_locator(source: &str) -> Option<(Option<SteamGridDbAssetKind>, u64)> {
    if !is_valid_opaque_locator(source) {
        return None;
    }
    let mut parts = source.strip_prefix("asset:")?.split(':');
    let first = parts.next()?;
    let (kind, asset_id) = match (SteamGridDbAssetKind::from_locator(first), parts.next()) {
        (Some(kind), Some(asset_id)) if parts.next().is_none() => (Some(kind), asset_id),
        (None, None) => (None, first),
        _ => return None,
    };
    let asset_id = asset_id
        .parse::<u64>()
        .ok()
        .filter(|asset_id| *asset_id > 0)?;
    Some((kind, asset_id))
}

fn parse_steamgriddb_assets(
    root: &Value,
    base_url: &str,
) -> Result<Vec<SteamGridDbAsset>, ProviderAdapterError> {
    if root.get("success").and_then(Value::as_bool) != Some(true)
        || root.get("page").and_then(Value::as_u64).is_none()
        || root.get("total").and_then(Value::as_u64).is_none()
        || root
            .get("limit")
            .and_then(Value::as_u64)
            .is_none_or(|limit| limit == 0 || limit > 50)
    {
        return Err(ProviderAdapterError::InvalidResponse);
    }
    let Some(assets) = root.get("data").and_then(Value::as_array) else {
        return Err(ProviderAdapterError::InvalidResponse);
    };
    let mut result = Vec::with_capacity(assets.len());
    for asset in assets {
        let Some(id) = asset.get("id").and_then(Value::as_u64).filter(|id| *id > 0) else {
            return Err(ProviderAdapterError::InvalidResponse);
        };
        let Some(source_url) = asset.get("url").and_then(Value::as_str) else {
            return Err(ProviderAdapterError::InvalidResponse);
        };
        if !is_provider_artwork_url_allowed(source_url, ProviderId::SteamGridDb, base_url) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        result.push(SteamGridDbAsset {
            id,
            source_url: source_url.to_owned(),
        });
    }
    if result.len()
        > root
            .get("limit")
            .and_then(Value::as_u64)
            .and_then(|limit| usize::try_from(limit).ok())
            .unwrap_or_default()
    {
        return Err(ProviderAdapterError::InvalidResponse);
    }
    Ok(result)
}

fn steamgriddb_success_response(
    response: ProviderResponse,
) -> Result<ProviderResponse, ProviderAdapterError> {
    match response.status() {
        200 => Ok(response),
        401 | 403 => Err(ProviderAdapterError::AuthenticationFailed),
        429 => Err(ProviderAdapterError::RateLimited),
        _ => Err(ProviderAdapterError::InvalidResponse),
    }
}

fn is_allowed_transport_url(url: &str) -> bool {
    let Some(parsed) = parse_safe_https_url(url, true) else {
        return false;
    };
    if let Ok(address) = parsed.host.parse::<std::net::IpAddr>() {
        return !is_forbidden_address(address);
    }
    let Ok(addresses) = (parsed.host.as_str(), 443).to_socket_addrs() else {
        return false;
    };
    let addresses = addresses.collect::<Vec<_>>();
    !addresses.is_empty()
        && addresses
            .iter()
            .all(|address| !is_forbidden_address(address.ip()))
}

fn is_provider_url_allowed(url: &str, provider_id: ProviderId, allow_query: bool) -> bool {
    let Some(parsed) = parse_safe_https_url(url, allow_query) else {
        return false;
    };
    is_approved_provider_host(provider_id, &parsed.host)
}

fn is_provider_artwork_url_allowed(url: &str, provider_id: ProviderId, base_url: &str) -> bool {
    let Some(parsed) = parse_safe_https_url(url, false) else {
        return false;
    };
    let Some(base) = parse_safe_https_url(base_url, true) else {
        return false;
    };
    is_approved_provider_host(provider_id, &parsed.host)
        && is_approved_provider_host(provider_id, &base.host)
}

struct SafeHttpsUrl {
    host: String,
}

fn parse_safe_https_url(url: &str, allow_query: bool) -> Option<SafeHttpsUrl> {
    let uri = url.parse::<ureq::http::Uri>().ok()?;
    if uri.scheme_str()? != "https" || uri.authority()?.as_str().contains('@') {
        return None;
    }
    if uri.port_u16().is_some_and(|port| port != 443) {
        return None;
    }
    let host = uri.host()?;
    if host.is_empty()
        || host.eq_ignore_ascii_case("localhost")
        || host.ends_with(".local")
        || host.ends_with('.')
        || host.chars().any(|character| character.is_control())
    {
        return None;
    }
    if host
        .parse::<std::net::IpAddr>()
        .is_ok_and(is_forbidden_address)
    {
        return None;
    }
    let has_query = uri
        .path_and_query()
        .is_some_and(|value| value.as_str().contains('?'));
    if has_query && !allow_query {
        return None;
    }
    Some(SafeHttpsUrl {
        host: host.to_owned(),
    })
}

fn is_forbidden_address(address: std::net::IpAddr) -> bool {
    match address {
        std::net::IpAddr::V4(address) => {
            address.is_loopback()
                || address.is_private()
                || address.is_link_local()
                || address.is_unspecified()
                || address.is_multicast()
        }
        std::net::IpAddr::V6(address) => {
            address.is_loopback()
                || address.is_unspecified()
                || address.is_multicast()
                || address.is_unique_local()
                || address.is_unicast_link_local()
        }
    }
}

fn is_approved_provider_host(provider_id: ProviderId, host: &str) -> bool {
    if host.eq_ignore_ascii_case("fixture.invalid") {
        return true;
    }
    let host = host.to_ascii_lowercase();
    match provider_id {
        ProviderId::Playmatch => {
            host == "playmatch.com"
                || host.ends_with(".playmatch.com")
                || host == "playmatch.retrorealm.dev"
        }
        ProviderId::GameTdb => host == "gametdb.com" || host.ends_with(".gametdb.com"),
        ProviderId::SteamGridDb => {
            (host == "steamgriddb.com" || host.ends_with(".steamgriddb.com"))
                || host == "steamusercontent.com"
                || host.ends_with(".steamusercontent.com")
        }
    }
}

fn is_valid_opaque_locator(value: &str) -> bool {
    let Some(locator) = value.strip_prefix("asset:") else {
        return false;
    };
    !locator.is_empty()
        && locator.len() <= 256
        && locator
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-' | b':'))
}

fn is_valid_external_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 256
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-' | b':'))
}

fn is_valid_steamgriddb_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 20
        && value.bytes().all(|byte| byte.is_ascii_digit())
        && value.parse::<u64>().is_ok_and(|id| id > 0)
}

fn is_valid_gametdb_identifier(value: &str) -> bool {
    gametdb_raw_identifier(value).is_some()
}

fn redact_url(url: &str) -> String {
    let end = url.find(['?', '#']).unwrap_or(url.len());
    if end == url.len() {
        url.to_owned()
    } else {
        format!("{}<redacted>", &url[..end])
    }
}

fn read_bounded_body(
    body: ureq::Body,
    max_response_bytes: usize,
) -> Result<Vec<u8>, ProviderTransportError> {
    body.into_with_config()
        .limit(max_response_bytes as u64)
        .read_to_vec()
        .map_err(|error| match error {
            ureq::Error::BodyExceedsLimit(_) => ProviderTransportError::ResponseTooLarge,
            _ => ProviderTransportError::Unavailable,
        })
}

/// Production session construction for the fixed provider roster.
pub struct ProductionProviderSessionFactory {
    playmatch_base_url: String,
    gametdb_base_url: String,
    steamgriddb_base_url: String,
}

impl ProductionProviderSessionFactory {
    /// Creates the immutable production endpoint configuration.
    pub fn new() -> Self {
        Self {
            playmatch_base_url: "https://playmatch.retrorealm.dev/api/v2".to_owned(),
            gametdb_base_url: "https://www.gametdb.com".to_owned(),
            steamgriddb_base_url: "https://www.steamgriddb.com/api/v2".to_owned(),
        }
    }

    /// Creates a fixtureable factory without changing session semantics.
    pub fn with_endpoints(
        playmatch_base_url: impl Into<String>,
        gametdb_base_url: impl Into<String>,
        steamgriddb_base_url: impl Into<String>,
    ) -> Self {
        Self {
            playmatch_base_url: playmatch_base_url.into(),
            gametdb_base_url: gametdb_base_url.into(),
            steamgriddb_base_url: steamgriddb_base_url.into(),
        }
    }

    /// Constructs one transient session per fixed provider without I/O.
    pub fn create_sessions(&self) -> Vec<Box<dyn EnrichmentProviderSession>> {
        vec![
            Box::new(PlaymatchSession::new(
                UreqTransport::new(),
                self.playmatch_base_url.clone(),
            )),
            Box::new(GameTdbSession::new(
                UreqTransport::new(),
                self.gametdb_base_url.clone(),
            )),
            Box::new(SteamGridDbSession::new(
                UreqTransport::new(),
                self.steamgriddb_base_url.clone(),
                KeyringSecureCredentialStore::new(),
            )),
        ]
    }
}

impl Default for ProductionProviderSessionFactory {
    fn default() -> Self {
        Self::new()
    }
}

/// Explicit credential validator for the write-only provider credential port.
///
/// The validator owns only the transport and documented read-only search
/// endpoint. Secret bytes are borrowed for one request and never returned,
/// logged, or placed in a DTO.
#[derive(Clone)]
pub struct SteamGridDbCredentialValidator<T> {
    transport: T,
    base_url: String,
}

impl<T> SteamGridDbCredentialValidator<T>
where
    T: ProviderTransport,
{
    /// Creates a validator with an explicit provider API endpoint.
    pub fn new(transport: T, base_url: impl Into<String>) -> Self {
        Self {
            transport,
            base_url: base_url.into(),
        }
    }
}

impl<T> CredentialValidator for SteamGridDbCredentialValidator<T>
where
    T: ProviderTransport,
{
    fn validate(&self, secret: &[u8]) -> Result<(), CredentialValidationError> {
        if secret.is_empty() {
            return Err(CredentialValidationError::Misconfigured);
        }
        let token =
            std::str::from_utf8(secret).map_err(|_| CredentialValidationError::Misconfigured)?;
        let mut headers = BTreeMap::new();
        headers.insert("authorization".to_owned(), format!("Bearer {token}"));
        let url = format!(
            "{}/search/autocomplete/{STEAMGRIDDB_CREDENTIAL_VALIDATION_TERM}",
            self.base_url.trim_end_matches('/')
        );
        if !is_provider_url_allowed(&url, ProviderId::SteamGridDb, false) {
            return Err(CredentialValidationError::Misconfigured);
        }
        let response = self
            .transport
            .send(ProviderRequest::new("GET", url, headers, Vec::new()))
            .map_err(|error| match error {
                ProviderTransportError::AuthenticationFailed => {
                    CredentialValidationError::InvalidCredentials
                }
                ProviderTransportError::RateLimited
                | ProviderTransportError::Timeout
                | ProviderTransportError::Unavailable
                | ProviderTransportError::ResponseTooLarge => {
                    CredentialValidationError::Unavailable
                }
            })?;
        match response.status() {
            200..=299 => Ok(()),
            429 => Err(CredentialValidationError::Unavailable),
            400..=499 => Err(CredentialValidationError::InvalidCredentials),
            _ => Err(CredentialValidationError::Unavailable),
        }
    }
}

fn parse_json(response: &ProviderResponse) -> Result<Value, ProviderAdapterError> {
    if response.body().len() > MAX_PROVIDER_RESPONSE_BYTES {
        return Err(ProviderAdapterError::Transport(
            ProviderTransportError::ResponseTooLarge,
        ));
    }
    serde_json::from_slice(response.body()).map_err(|_| ProviderAdapterError::InvalidResponse)
}

fn bounded_response_body(response: &ProviderResponse) -> Result<Vec<u8>, ProviderAdapterError> {
    if response.body().len() > MAX_PROVIDER_RESPONSE_BYTES {
        return Err(ProviderAdapterError::Transport(
            ProviderTransportError::ResponseTooLarge,
        ));
    }
    Ok(response.body().to_vec())
}

fn map_transport_error(error: ProviderTransportError) -> ProviderAdapterError {
    match error {
        ProviderTransportError::AuthenticationFailed => ProviderAdapterError::AuthenticationFailed,
        ProviderTransportError::RateLimited => ProviderAdapterError::RateLimited,
        other => ProviderAdapterError::Transport(other),
    }
}

fn retryable_transport_error(error: &ProviderTransportError) -> bool {
    matches!(
        error,
        ProviderTransportError::Timeout
            | ProviderTransportError::Unavailable
            | ProviderTransportError::RateLimited
    )
}

fn map_hydration_error(error: ProviderAdapterError) -> HydrationProviderError {
    match error {
        ProviderAdapterError::AuthenticationFailed => HydrationProviderError::AuthenticationFailed,
        ProviderAdapterError::RateLimited => HydrationProviderError::RateLimited,
        ProviderAdapterError::InvalidResponse => HydrationProviderError::InvalidResponse,
        ProviderAdapterError::UnsupportedCapability => {
            HydrationProviderError::UnsupportedCapability
        }
        ProviderAdapterError::Transport(ProviderTransportError::Timeout) => {
            HydrationProviderError::Timeout
        }
        ProviderAdapterError::Transport(ProviderTransportError::Unavailable)
        | ProviderAdapterError::Transport(ProviderTransportError::ResponseTooLarge) => {
            HydrationProviderError::Unavailable
        }
        ProviderAdapterError::Transport(ProviderTransportError::RateLimited) => {
            HydrationProviderError::RateLimited
        }
        ProviderAdapterError::Transport(ProviderTransportError::AuthenticationFailed) => {
            HydrationProviderError::AuthenticationFailed
        }
    }
}

#[cfg(test)]
mod tests {
    use std::io::Cursor;

    use super::{ProviderTransportError, read_bounded_body, retryable_transport_error};

    #[test]
    fn bounded_body_reader_rejects_excess_bytes_before_returning_a_buffer() {
        let body = ureq::Body::builder().reader(Cursor::new(vec![1_u8; 4]));

        assert_eq!(
            read_bounded_body(body, 3),
            Err(ProviderTransportError::ResponseTooLarge)
        );
    }

    #[test]
    fn retry_policy_is_bounded_to_transient_transport_failures() {
        assert!(retryable_transport_error(&ProviderTransportError::Timeout));
        assert!(retryable_transport_error(
            &ProviderTransportError::Unavailable
        ));
        assert!(retryable_transport_error(
            &ProviderTransportError::RateLimited
        ));
        assert!(!retryable_transport_error(
            &ProviderTransportError::AuthenticationFailed
        ));
        assert!(!retryable_transport_error(
            &ProviderTransportError::ResponseTooLarge
        ));
    }
}
