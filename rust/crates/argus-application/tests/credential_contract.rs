use argus_application::{
    CredentialMutationError, CredentialValidationError, CredentialValidator,
    MetadataProviderService, ProviderId, ProviderReadinessState, SecureCredentialStore,
};

#[derive(Default)]
struct FakeStore {
    secret: Option<Vec<u8>>,
    fail_set: bool,
    fail_remove: bool,
    fail_is_configured: bool,
    fail_with_secret: bool,
}

impl SecureCredentialStore for FakeStore {
    fn set(
        &mut self,
        provider_id: ProviderId,
        secret: &[u8],
    ) -> Result<(), CredentialMutationError> {
        assert_eq!(provider_id, ProviderId::SteamGridDb);
        if self.fail_set {
            return Err(CredentialMutationError::StoreUnavailable);
        }
        self.secret = Some(secret.to_vec());
        Ok(())
    }

    fn remove(&mut self, provider_id: ProviderId) -> Result<(), CredentialMutationError> {
        assert_eq!(provider_id, ProviderId::SteamGridDb);
        if self.fail_remove {
            return Err(CredentialMutationError::StoreUnavailable);
        }
        self.secret = None;
        Ok(())
    }

    fn is_configured(&mut self, provider_id: ProviderId) -> Result<bool, CredentialMutationError> {
        assert_eq!(provider_id, ProviderId::SteamGridDb);
        if self.fail_is_configured {
            return Err(CredentialMutationError::StoreUnavailable);
        }
        Ok(self.secret.is_some())
    }

    fn with_secret<T>(
        &mut self,
        provider_id: ProviderId,
        operation: &mut dyn FnMut(&[u8]) -> T,
    ) -> Result<T, CredentialMutationError> {
        assert_eq!(provider_id, ProviderId::SteamGridDb);
        if self.fail_with_secret {
            return Err(CredentialMutationError::StoreUnavailable);
        }
        let secret = self
            .secret
            .as_deref()
            .ok_or(CredentialMutationError::StoreUnavailable)?;
        Ok(operation(secret))
    }
}

struct FakeValidator {
    result: Result<(), CredentialValidationError>,
}

impl FakeValidator {
    fn validate(&self, secret: &[u8]) -> Result<(), CredentialValidationError> {
        assert_eq!(secret, b"secret");
        self.result
    }
}

impl CredentialValidator for FakeValidator {
    fn validate(&self, secret: &[u8]) -> Result<(), CredentialValidationError> {
        self.validate(secret)
    }
}

#[test]
fn credential_set_writes_securely_then_reports_ready_without_returning_secret() {
    let store = FakeStore::default();
    let validator = FakeValidator { result: Ok(()) };
    let mut service = MetadataProviderService::new(store, validator);

    let readiness = service
        .set_steamgriddb_credential(b"secret")
        .expect("credential mutation should succeed");

    assert_eq!(readiness.state(), ProviderReadinessState::Ready);
    assert!(readiness.credential_configured());
}

#[test]
fn invalid_and_transient_validation_keep_the_credential_configured() {
    let invalid = MetadataProviderService::new(
        FakeStore::default(),
        FakeValidator {
            result: Err(CredentialValidationError::InvalidCredentials),
        },
    )
    .set_steamgriddb_credential(b"secret")
    .expect("invalid credentials remain a successful secure write");
    assert_eq!(invalid.state(), ProviderReadinessState::InvalidCredentials);
    assert!(invalid.credential_configured());

    let transient = MetadataProviderService::new(
        FakeStore::default(),
        FakeValidator {
            result: Err(CredentialValidationError::Unavailable),
        },
    )
    .set_steamgriddb_credential(b"secret")
    .expect("transient validation remains configured");
    assert_eq!(transient.state(), ProviderReadinessState::Unavailable);
    assert!(transient.credential_configured());
}

#[test]
fn misconfigured_validation_is_distinct_from_unavailable_validation() {
    let readiness = MetadataProviderService::new(
        FakeStore::default(),
        FakeValidator {
            result: Err(CredentialValidationError::Misconfigured),
        },
    )
    .set_steamgriddb_credential(b"secret")
    .expect("misconfigured validation remains a secure-write result");

    assert_eq!(readiness.state(), ProviderReadinessState::Misconfigured);
    assert!(readiness.credential_configured());
}

#[test]
fn secure_store_failures_do_not_fabricate_readiness_or_replace_prior_state() {
    let mut failed_set = MetadataProviderService::new(
        FakeStore {
            fail_set: true,
            ..FakeStore::default()
        },
        FakeValidator { result: Ok(()) },
    );
    assert_eq!(
        failed_set.set_steamgriddb_credential(b"secret"),
        Err(CredentialMutationError::StoreUnavailable)
    );
    assert_eq!(
        failed_set.readiness().state(),
        ProviderReadinessState::MissingCredentials
    );

    let mut failed_remove = MetadataProviderService::new(
        FakeStore {
            fail_remove: true,
            ..FakeStore::default()
        },
        FakeValidator { result: Ok(()) },
    );
    let before_remove = failed_remove
        .set_steamgriddb_credential(b"secret")
        .expect("fixture credential");
    assert_eq!(
        failed_remove.remove_steamgriddb_credential(),
        Err(CredentialMutationError::StoreUnavailable)
    );
    assert_eq!(failed_remove.readiness(), before_remove);
}

#[test]
fn readiness_refresh_is_network_free_and_distinguishes_missing_storage() {
    let mut configured =
        MetadataProviderService::new(FakeStore::default(), FakeValidator { result: Ok(()) });
    configured
        .set_steamgriddb_credential(b"secret")
        .expect("fixture credential");
    assert_eq!(
        configured
            .refresh_readiness_from_store()
            .expect("configured store"),
        configured.readiness()
    );

    let mut missing =
        MetadataProviderService::new(FakeStore::default(), FakeValidator { result: Ok(()) });
    let readiness = missing
        .refresh_readiness_from_store()
        .expect("missing store is a valid readiness fact");
    assert_eq!(
        readiness.state(),
        ProviderReadinessState::MissingCredentials
    );
    assert!(!readiness.credential_configured());
}

#[test]
fn secure_store_read_failure_projects_unavailable_readiness() {
    let mut service = MetadataProviderService::new(
        FakeStore {
            fail_is_configured: true,
            ..FakeStore::default()
        },
        FakeValidator { result: Ok(()) },
    );

    assert_eq!(
        service.refresh_readiness_from_store(),
        Err(CredentialMutationError::StoreUnavailable)
    );
    assert_eq!(
        service.readiness().state(),
        ProviderReadinessState::Unavailable
    );
    assert!(!service.readiness().credential_configured());
}

#[test]
fn secure_store_validation_read_failure_projects_unavailable_readiness() {
    let mut service = MetadataProviderService::new(
        FakeStore {
            fail_with_secret: true,
            ..FakeStore::default()
        },
        FakeValidator { result: Ok(()) },
    );

    assert_eq!(
        service.set_steamgriddb_credential(b"secret"),
        Err(CredentialMutationError::StoreUnavailable)
    );
    assert_eq!(
        service.readiness().state(),
        ProviderReadinessState::Unavailable
    );
    assert!(service.readiness().credential_configured());
}
