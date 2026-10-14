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
    #[cfg(all(target_os = "android", not(feature = "test-support")))]
    keyring::cli::use_android_native_store(&HashMap::new())
        .map_err(|_| CredentialMutationError::StoreUnavailable)?;

    Ok(())
}

/// Initializes native credential storage for the explicit live qualification suite.
///
/// Ordinary test-support startup deliberately skips native storage setup. The
/// ignored live suite calls this function only after its operator prerequisites
/// have been checked.
#[cfg(feature = "test-support")]
#[doc(hidden)]
pub fn initialize_secure_store_for_live_qualification() -> Result<(), CredentialMutationError> {
    #[cfg(target_os = "android")]
    keyring::cli::use_android_native_store(&HashMap::new())
        .map_err(|_| CredentialMutationError::StoreUnavailable)?;

    Ok(())
}

/// Rust-owned keyring implementation of the application credential port.
#[derive(Clone, Debug)]
pub struct KeyringSecureCredentialStore {
    service_name: &'static str,
    #[cfg(feature = "test-support")]
    native_access_allowed: bool,
}

impl Default for KeyringSecureCredentialStore {
    fn default() -> Self {
        Self::new()
    }
}

impl KeyringSecureCredentialStore {
    /// Creates a store using the application's stable keyring service name.
    pub const fn new() -> Self {
        Self {
            service_name: SERVICE_NAME,
            #[cfg(feature = "test-support")]
            native_access_allowed: false,
        }
    }

    /// Creates the platform store used by normal application composition.
    ///
    /// This explicit constructor preserves platform access when the crate is
    /// compiled with `test-support`; test hosts should select the in-memory
    /// store through runtime test configuration.
    #[doc(hidden)]
    pub fn new_for_application() -> Self {
        Self {
            service_name: SERVICE_NAME,
            #[cfg(feature = "test-support")]
            native_access_allowed: true,
        }
    }

    /// Creates a platform store for the explicitly invoked live-provider suite.
    ///
    /// This constructor is reserved for the ignored live qualification test
    /// after its documented credential prerequisites have been checked.
    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    pub fn new_for_live_qualification() -> Self {
        Self {
            service_name: SERVICE_NAME,
            native_access_allowed: true,
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

    /// Stops test-support builds before they can open a native credential store.
    ///
    /// Automated tests must opt into an in-memory store at runtime composition;
    /// accidental use of this platform adapter is a test failure, not a prompt.
    #[cfg(feature = "test-support")]
    fn reject_unless_native_access_is_explicit(&self) {
        assert!(
            self.native_access_allowed,
            "test-support build attempted platform credential-store access"
        );
    }
}

impl SecureCredentialStore for KeyringSecureCredentialStore {
    fn set(
        &mut self,
        provider_id: ProviderId,
        secret: &[u8],
    ) -> Result<(), CredentialMutationError> {
        #[cfg(feature = "test-support")]
        self.reject_unless_native_access_is_explicit();
        let entry = self.entry(provider_id)?;
        entry
            .set_secret(secret)
            .map_err(|_| CredentialMutationError::StoreUnavailable)
    }

    fn remove(&mut self, provider_id: ProviderId) -> Result<(), CredentialMutationError> {
        #[cfg(feature = "test-support")]
        self.reject_unless_native_access_is_explicit();
        let entry = self.entry(provider_id)?;
        match entry.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(_) => Err(CredentialMutationError::StoreUnavailable),
        }
    }

    fn is_configured(&mut self, provider_id: ProviderId) -> Result<bool, CredentialMutationError> {
        #[cfg(feature = "test-support")]
        self.reject_unless_native_access_is_explicit();
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
        #[cfg(feature = "test-support")]
        self.reject_unless_native_access_is_explicit();
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
    #[cfg(feature = "test-support")]
    use std::panic::{AssertUnwindSafe, catch_unwind};

    #[cfg(feature = "test-support")]
    use argus_application::{ProviderId, SecureCredentialStore};

    use super::KeyringSecureCredentialStore;
    use super::SERVICE_NAME;

    #[test]
    fn service_name_is_stable_and_does_not_include_a_secret() {
        assert_eq!(
            KeyringSecureCredentialStore::new().service_name,
            SERVICE_NAME
        );
        assert!(!SERVICE_NAME.contains("secret"));
    }

    #[cfg(feature = "test-support")]
    #[test]
    fn test_support_build_rejects_platform_store_before_native_access() {
        let mut store = KeyringSecureCredentialStore::new();

        assert!(
            catch_unwind(AssertUnwindSafe(|| {
                let _ = store.set(ProviderId::SteamGridDb, b"synthetic");
            }))
            .is_err()
        );
        assert!(
            catch_unwind(AssertUnwindSafe(|| {
                let _ = store.remove(ProviderId::SteamGridDb);
            }))
            .is_err()
        );
        assert!(
            catch_unwind(AssertUnwindSafe(|| {
                let _ = store.is_configured(ProviderId::SteamGridDb);
            }))
            .is_err()
        );
        assert!(
            catch_unwind(AssertUnwindSafe(|| {
                let _ = store.with_secret(ProviderId::SteamGridDb, &mut |_| ());
            }))
            .is_err()
        );
    }

    #[cfg(feature = "test-support")]
    #[test]
    fn application_store_retains_native_access_when_test_support_is_enabled() {
        assert!(!KeyringSecureCredentialStore::new().native_access_allowed);
        assert!(KeyringSecureCredentialStore::new_for_application().native_access_allowed);
        assert!(KeyringSecureCredentialStore::new_for_live_qualification().native_access_allowed);
    }
}
