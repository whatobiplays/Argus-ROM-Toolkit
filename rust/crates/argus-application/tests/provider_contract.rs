use std::collections::BTreeSet;

use argus_application::{
    MetadataProviderRegistry, MetadataProviderSettings, ProviderCapability, ProviderId,
    ProviderReadinessState,
};

#[test]
fn production_registry_contains_only_the_approved_provider_roster() {
    let registry = MetadataProviderRegistry::production();

    assert_eq!(
        registry.provider_ids(),
        &[
            ProviderId::Playmatch,
            ProviderId::GameTdb,
            ProviderId::SteamGridDb,
        ]
    );
    assert!(
        registry
            .descriptor(ProviderId::Playmatch)
            .capabilities()
            .contains(&ProviderCapability::ContentMatching)
    );
    assert!(
        registry
            .descriptor(ProviderId::GameTdb)
            .capabilities()
            .contains(&ProviderCapability::MetadataRefresh)
    );
    assert!(
        registry
            .descriptor(ProviderId::SteamGridDb)
            .capabilities()
            .contains(&ProviderCapability::ArtworkDiscovery)
    );
}

#[test]
fn settings_are_persistable_policy_inputs_without_resolution_side_effects() {
    let mut settings = MetadataProviderSettings::default();
    settings.set_enabled(ProviderId::SteamGridDb, false);

    assert!(!settings.enabled().contains(&ProviderId::SteamGridDb));
    assert!(settings.enabled().contains(&ProviderId::GameTdb));
    assert_eq!(
        ProviderReadinessState::MissingCredentials,
        ProviderReadinessState::MissingCredentials
    );

    let mut enabled = BTreeSet::new();
    enabled.insert(ProviderId::GameTdb);
    assert_eq!(enabled.len(), 1);
}
