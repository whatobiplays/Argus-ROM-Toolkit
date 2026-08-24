//! Platform-backed secure credential storage.
//!
//! This module is the only infrastructure implementation of the application's
//! [`SecureCredentialStore`](argus_application::SecureCredentialStore) port.
//! Provider secrets are written, read, and deleted here; neither Flutter nor
//! native UI/application code receives ownership of the secret bytes.

#[cfg(target_os = "android")]
use std::collections::HashMap;

use argus_application::{CredentialMutationError, ProviderId, SecureCredentialStore};
use zeroize::Zeroizing;

const SERVICE_NAME: &str = "org.argus-rom-toolkit.providers";
const STEAMGRIDDB_ACCOUNT: &str = "steamgriddb";

#[cfg(not(target_os = "android"))]
type PlatformEntry = keyring::Entry;

#[cfg(target_os = "android")]
type PlatformEntry = keyring_core::Entry;

/// Initializes the platform adapter used by the secure credential store.
///
/// On Android this is the one Rust-side hook that selects the Keystore-backed
/// keyring adapter. It performs no credential operation and accepts no secret
/// bytes. Other platforms initialize lazily when an entry is opened.
pub fn initialize_secure_store() -> Result<(), CredentialMutationError> {
    #[cfg(target_os = "android")]
    keyring::cli::use_android_native_store(&HashMap::new())
        .map_err(|_| CredentialMutationError::StoreUnavailable)?;

    Ok(())
}

/// Rust-owned keyring implementation of the application credential port.
#[derive(Clone, Debug)]
pub struct KeyringSecureCredentialStore {
    service_name: &'static str,
}

impl Default for KeyringSecureCredentialStore {
    fn default() -> Self {
        Self {
            service_name: SERVICE_NAME,
        }
    }
}

impl KeyringSecureCredentialStore {
    /// Creates a store using the application's stable keyring service name.
    pub const fn new() -> Self {
        Self {
            service_name: SERVICE_NAME,
        }
    }

    fn account(provider_id: ProviderId) -> Option<&'static str> {
        match provider_id {
            ProviderId::SteamGridDb => Some(STEAMGRIDDB_ACCOUNT),
            ProviderId::Playmatch | ProviderId::GameTdb => None,
        }
    }

    fn entry(&self, provider_id: ProviderId) -> Result<PlatformEntry, CredentialMutationError> {
        let account =
            Self::account(provider_id).ok_or(CredentialMutationError::UnsupportedProvider)?;
        PlatformEntry::new(self.service_name, account)
            .map_err(|_| CredentialMutationError::StoreUnavailable)
    }
}

impl SecureCredentialStore for KeyringSecureCredentialStore {
    fn set(
        &mut self,
        provider_id: ProviderId,
        secret: &[u8],
    ) -> Result<(), CredentialMutationError> {
        let entry = self.entry(provider_id)?;
        entry
            .set_secret(secret)
            .map_err(|_| CredentialMutationError::StoreUnavailable)
    }

    fn remove(&mut self, provider_id: ProviderId) -> Result<(), CredentialMutationError> {
        let entry = self.entry(provider_id)?;
        match entry.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(_) => Err(CredentialMutationError::StoreUnavailable),
        }
    }

    fn is_configured(&mut self, provider_id: ProviderId) -> Result<bool, CredentialMutationError> {
        let entry = self.entry(provider_id)?;
        match entry.get_secret() {
            Ok(secret) => {
                let secret = Zeroizing::new(secret);
                let configured = !secret.is_empty();
                Ok(configured)
            }
            Err(keyring::Error::NoEntry) => Ok(false),
            Err(_) => Err(CredentialMutationError::StoreUnavailable),
        }
    }

    fn with_secret<T>(
        &mut self,
        provider_id: ProviderId,
        operation: &mut dyn FnMut(&[u8]) -> T,
    ) -> Result<T, CredentialMutationError> {
        let entry = self.entry(provider_id)?;
        let secret = Zeroizing::new(
            entry
                .get_secret()
                .map_err(|_| CredentialMutationError::StoreUnavailable)?,
        );
        Ok(operation(&secret))
    }
}

#[cfg(test)]
mod tests {
    use super::{KeyringSecureCredentialStore, SERVICE_NAME};

    #[test]
    fn service_name_is_stable_and_does_not_include_a_secret() {
        assert_eq!(
            KeyringSecureCredentialStore::new().service_name,
            SERVICE_NAME
        );
        assert!(!SERVICE_NAME.contains("secret"));
    }
}
