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
        if !is_valid_identity(identity) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let Some(provider_platform_id) = ProviderId::Playmatch
            .platform_mapping(platform_id)
            .mapped_id()
        else {
            return Err(ProviderAdapterError::UnsupportedCapability);
        };
        let body = serde_json::json!({
            "platform": provider_platform_id,
            "identity": identity,
        })
        .to_string()
        .into_bytes();
        let response = self.send("/match", body, BTreeMap::new())?;
        let root = parse_json(&response)?;
        let Some(matches) = root.get("matches").and_then(Value::as_array) else {
            return Err(ProviderAdapterError::InvalidResponse);
        };
        let mut evidence = Vec::with_capacity(matches.len());
        for item in matches {
            let Some(external_game_id) = item.get("external_game_id").and_then(Value::as_str)
            else {
                return Err(ProviderAdapterError::InvalidResponse);
            };
            if !is_valid_external_id(external_game_id) {
                return Err(ProviderAdapterError::InvalidResponse);
            }
            let Some(response_platform) = item.get("platform").and_then(Value::as_str) else {
                return Err(ProviderAdapterError::InvalidResponse);
            };
            let Some(response_identity) = item.get("identity").and_then(Value::as_str) else {
                return Err(ProviderAdapterError::InvalidResponse);
            };
            if !is_valid_identity(response_identity) {
                return Err(ProviderAdapterError::InvalidResponse);
            }
            if response_platform != provider_platform_id {
                continue;
            }
            evidence.push(ExactMatchEvidence::Playmatch {
                game_content_id,
                platform_id,
                external_game_id: external_game_id.to_owned(),
                submitted_identity: identity.to_owned(),
                response_identity: response_identity.to_owned(),
            });
        }
        Ok(evidence)
    }

    fn send(
        &self,
        path: &str,
        body: Vec<u8>,
        headers: BTreeMap<String, String>,
    ) -> Result<ProviderResponse, ProviderAdapterError> {
        let url = format!("{}{}", self.base_url, path);
        if !is_provider_url_allowed(&url, ProviderId::Playmatch, true) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let response = self
            .transport
            .send(ProviderRequest::new("POST", url, headers, body))
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
        let Some(provider_platform_id) = ProviderId::GameTdb
            .platform_mapping(platform_id)
            .mapped_id()
        else {
            return Err(ProviderAdapterError::UnsupportedCapability);
        };
        let body = serde_json::json!({
            "platform": provider_platform_id,
            "identifier": native_identifier,
        })
        .to_string()
        .into_bytes();
        let url = format!("{}/lookup", self.base_url);
        if !is_provider_url_allowed(&url, ProviderId::GameTdb, true) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let response = self
            .transport
            .send(ProviderRequest::new("POST", url, BTreeMap::new(), body))
            .map_err(map_transport_error)?;
        if response.status() == 404 {
            return Ok(None);
        }
        if response.status() != 200 {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let root = parse_json(&response)?;
        let Some(game) = root.get("game") else {
            return Err(ProviderAdapterError::InvalidResponse);
        };
        let Some(external_game_id) = game.get("id").and_then(Value::as_str) else {
            return Err(ProviderAdapterError::InvalidResponse);
        };
        if !is_valid_external_id(external_game_id) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        if game
            .get("platform")
            .and_then(Value::as_str)
            .is_some_and(|value| value != provider_platform_id)
        {
            return Ok(None);
        }
        if game
            .get("identifier")
            .and_then(Value::as_str)
            .is_some_and(|value| value != native_identifier)
        {
            return Ok(None);
        }
        let title = game.get("title").and_then(Value::as_str).map(str::to_owned);
        let region = game
            .get("region")
            .and_then(Value::as_str)
            .map(str::to_owned);
        let language = game
            .get("language")
            .and_then(Value::as_str)
            .map(str::to_owned);
        let revision = game
            .get("revision")
            .and_then(Value::as_u64)
            .ok_or(ProviderAdapterError::InvalidResponse)?;
        Ok(Some(ProviderMetadata::new(
            ProviderId::GameTdb,
            external_game_id,
            revision,
            region,
            language,
            0,
            None,
            title,
            Vec::new(),
            None,
            None,
            Vec::new(),
            Vec::new(),
            Vec::new(),
            Vec::new(),
            100,
            format!("gametdb:{external_game_id}"),
        )))
    }

    /// Discovers credential-free artwork references for one exact record.
    pub fn discover_artwork(
        &self,
        external_game_id: &str,
    ) -> Result<Vec<ArtworkCandidate>, ProviderAdapterError> {
        if !is_valid_external_id(external_game_id) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let url = format!("{}/artwork/{external_game_id}", self.base_url);
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
        let root = parse_json(&response)?;
        parse_artwork_candidates(&root, ProviderId::GameTdb, &self.base_url)
    }

    /// Downloads original bytes from a credential-free URL or opaque
    /// GameTDB asset locator returned by the artwork endpoint.
    pub fn download_artwork(
        &self,
        external_game_id: &str,
        source: &str,
    ) -> Result<Vec<u8>, ProviderAdapterError> {
        let url = if is_provider_artwork_url_allowed(source, ProviderId::GameTdb, &self.base_url) {
            source.to_owned()
        } else if let Some(asset_id) = source.strip_prefix("asset:") {
            if !is_valid_opaque_locator(source) || !is_valid_external_id(external_game_id) {
                return Err(ProviderAdapterError::InvalidResponse);
            }
            let url = format!(
                "{}/artwork/{external_game_id}/asset/{asset_id}",
                self.base_url
            );
            if !is_provider_url_allowed(&url, ProviderId::GameTdb, true) {
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
        if !is_valid_external_id(external_game_id) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let token =
            std::str::from_utf8(secret).map_err(|_| ProviderAdapterError::UnsupportedCapability)?;
        let mut headers = BTreeMap::new();
        headers.insert("authorization".to_owned(), format!("Bearer {token}"));
        let url = format!("{}/artwork/{}", self.base_url, external_game_id);
        if !is_provider_url_allowed(&url, ProviderId::SteamGridDb, true) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let response = self
            .transport
            .send(ProviderRequest::new("GET", url, headers, Vec::new()))
            .map_err(map_transport_error)?;
        if response.status() != 200 {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let root = parse_json(&response)?;
        parse_artwork_candidates(&root, ProviderId::SteamGridDb, &self.base_url)
    }

    /// Downloads original bytes for an opaque provider asset locator.
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
        let asset_id = asset_locator
            .strip_prefix("asset:")
            .filter(|_| is_valid_opaque_locator(asset_locator))
            .ok_or(ProviderAdapterError::InvalidResponse)?;
        if !is_valid_external_id(external_game_id) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let mut headers = BTreeMap::new();
        headers.insert("authorization".to_owned(), format!("Bearer {token}"));
        let url = format!(
            "{}/artwork/{external_game_id}/asset/{asset_id}",
            self.base_url
        );
        if !is_provider_url_allowed(&url, ProviderId::SteamGridDb, true) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let response = self
            .transport
            .send(ProviderRequest::new("GET", url, headers, Vec::new()))
            .map_err(map_transport_error)?;
        if response.status() != 200 {
            return Err(ProviderAdapterError::InvalidResponse);
        }
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

fn parse_artwork_candidates(
    root: &Value,
    provider_id: ProviderId,
    base_url: &str,
) -> Result<Vec<ArtworkCandidate>, ProviderAdapterError> {
    let Some(assets) = root.get("assets").and_then(Value::as_array) else {
        return Err(ProviderAdapterError::InvalidResponse);
    };
    let mut result = Vec::with_capacity(assets.len());
    for asset in assets {
        let Some(id) = asset.get("id").and_then(Value::as_str) else {
            return Err(ProviderAdapterError::InvalidResponse);
        };
        if !is_valid_external_id(id) {
            return Err(ProviderAdapterError::InvalidResponse);
        }
        let Some(kind) = asset.get("type").and_then(Value::as_str) else {
            return Err(ProviderAdapterError::InvalidResponse);
        };
        let artwork_type = match kind {
            "cover_front" => ArtworkType::CoverFront,
            "cover_back" => ArtworkType::CoverBack,
            "screenshot" => ArtworkType::Screenshot,
            "logo" => ArtworkType::Logo,
            "icon" => ArtworkType::Icon,
            "background" => ArtworkType::Background,
            "banner" => ArtworkType::Banner,
            _ => continue,
        };
        let revision = asset
            .get("revision")
            .and_then(Value::as_u64)
            .ok_or(ProviderAdapterError::InvalidResponse)?;
        let width = asset
            .get("width")
            .and_then(Value::as_u64)
            .map(|value| u32::try_from(value).map_err(|_| ProviderAdapterError::InvalidResponse))
            .transpose()?;
        let height = asset
            .get("height")
            .and_then(Value::as_u64)
            .map(|value| u32::try_from(value).map_err(|_| ProviderAdapterError::InvalidResponse))
            .transpose()?;
        let region = asset
            .get("region")
            .and_then(Value::as_str)
            .map(str::to_owned);
        let language = asset
            .get("language")
            .and_then(Value::as_str)
            .map(str::to_owned);
        let quality = asset.get("quality").and_then(Value::as_u64).unwrap_or(0);
        let quality = u8::try_from(quality)
            .ok()
            .filter(|value| *value <= 100)
            .ok_or(ProviderAdapterError::InvalidResponse)?;
        let discovered_at = asset
            .get("discovered_at")
            .and_then(|value| {
                value
                    .as_i64()
                    .or_else(|| value.as_str().and_then(|value| value.parse().ok()))
            })
            .unwrap_or_default();
        let source = asset
            .get("url")
            .and_then(Value::as_str)
            .filter(|url| {
                provider_id != ProviderId::SteamGridDb
                    && is_provider_artwork_url_allowed(url, provider_id, base_url)
            })
            .map_or_else(|| format!("asset:{id}"), str::to_owned);
        result.push(
            ArtworkCandidate::new(provider_id, id, artwork_type, source, revision)
                .with_details(region, language, width, height, quality)
                .with_discovered_at(discovered_at),
        );
    }
    Ok(result)
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
        ProviderId::Playmatch => host == "playmatch.com" || host.ends_with(".playmatch.com"),
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

fn is_valid_identity(value: &str) -> bool {
    !value.is_empty() && value.len() <= 512 && !value.chars().any(char::is_whitespace)
}

fn is_valid_gametdb_identifier(value: &str) -> bool {
    is_valid_external_id(value) && (value.starts_with("product:") || value.starts_with("native:"))
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
            playmatch_base_url: "https://api.playmatch.com/v1".to_owned(),
            gametdb_base_url: "https://api.gametdb.com/v1".to_owned(),
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
/// The validator owns only the transport and endpoint. Secret bytes are
/// borrowed for one request and never returned, logged, or placed in a DTO.
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
        let url = format!("{}/auth/validate", self.base_url);
        if !is_provider_url_allowed(&url, ProviderId::SteamGridDb, true) {
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
