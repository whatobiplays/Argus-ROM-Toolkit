//! Phase 003 durable refresh issue projection contracts.
//!
//! These tests pin the closed vocabulary, the deterministic aggregation, and
//! the checked arithmetic that make a `library_refresh` reaching
//! `CompletedWithIssues` explain itself without leaking raw provider, path,
//! locator, or secret detail.

use argus_application::{
    ArtworkAssetStoreError, HydrationIssueKind, HydrationIssueSource, HydrationProviderError,
    ProviderId, RefreshIssueAccumulator, RefreshIssueFact, RefreshIssueKind, RefreshIssueReason,
    RefreshIssueSummary,
};

const ALL_KINDS: [RefreshIssueKind; 7] = [
    RefreshIssueKind::Matching,
    RefreshIssueKind::Metadata,
    RefreshIssueKind::ArtworkDiscovery,
    RefreshIssueKind::ArtworkDownload,
    RefreshIssueKind::AssetStore,
    RefreshIssueKind::Content,
    RefreshIssueKind::Scope,
];

const ALL_REASONS: [RefreshIssueReason; 25] = [
    RefreshIssueReason::ProviderAuthenticationFailed,
    RefreshIssueReason::ProviderAuthorizationFailed,
    RefreshIssueReason::ProviderMisconfigured,
    RefreshIssueReason::ProviderRateLimited,
    RefreshIssueReason::ProviderTimeout,
    RefreshIssueReason::ProviderUnavailable,
    RefreshIssueReason::ProviderInvalidResponse,
    RefreshIssueReason::ProviderUnsupportedCapability,
    RefreshIssueReason::ArtworkAssetTooLarge,
    RefreshIssueReason::ArtworkAssetInvalidImage,
    RefreshIssueReason::ArtworkAssetDimensionsTooLarge,
    RefreshIssueReason::ArtworkAssetStoreUnavailable,
    RefreshIssueReason::ContentUnavailable,
    RefreshIssueReason::ContentMalformedOrUnsupported,
    RefreshIssueReason::ContentEncryptedUnsupported,
    RefreshIssueReason::ContentDependencyMissing,
    RefreshIssueReason::ContentResourceLimitExceeded,
    RefreshIssueReason::ContentChangedDuringRefresh,
    RefreshIssueReason::ContentIdentityUnsupported,
    RefreshIssueReason::ContentIdentificationFailed,
    RefreshIssueReason::ContentGroupingFailed,
    RefreshIssueReason::ContentRefreshFailed,
    RefreshIssueReason::ScopeRootNotAdmitted,
    RefreshIssueReason::ScopeRootScanIncomplete,
    RefreshIssueReason::ScopeRootScanFailed,
];

fn content_fact(reason: RefreshIssueReason, occurrences: u64) -> RefreshIssueFact {
    RefreshIssueFact::new(RefreshIssueKind::Content, reason, None, occurrences)
        .expect("content fact")
}

#[test]
fn refresh_issue_kinds_round_trip_through_persisted_keys() {
    let mut keys = Vec::new();
    for kind in ALL_KINDS {
        let key = kind.as_str();
        assert!(!keys.contains(&key), "duplicate kind key {key}");
        keys.push(key);
        assert_eq!(
            RefreshIssueKind::from_persisted(key).expect("decodable kind"),
            kind
        );
    }
    assert!(RefreshIssueKind::from_persisted("unknown_kind").is_err());
}

#[test]
fn refresh_issue_reasons_round_trip_through_persisted_keys() {
    let mut keys = Vec::new();
    for reason in ALL_REASONS {
        let key = reason.as_str();
        assert!(!keys.contains(&key), "duplicate reason key {key}");
        keys.push(key);
        assert_eq!(
            RefreshIssueReason::from_persisted(key).expect("decodable reason"),
            reason
        );
    }
    assert!(RefreshIssueReason::from_persisted("unknown_reason").is_err());
}

#[test]
fn refresh_issue_fact_rejects_impossible_reason_and_category_pairing() {
    // A content reason can never describe a provider matching failure, and a
    // scope reason can never describe local content processing.
    assert!(
        RefreshIssueFact::new(
            RefreshIssueKind::Matching,
            RefreshIssueReason::ContentGroupingFailed,
            Some(ProviderId::GameTdb),
            1,
        )
        .is_err()
    );
    assert!(
        RefreshIssueFact::new(
            RefreshIssueKind::Content,
            RefreshIssueReason::ScopeRootScanFailed,
            None,
            1,
        )
        .is_err()
    );
    assert!(
        RefreshIssueFact::new(
            RefreshIssueKind::AssetStore,
            RefreshIssueReason::ProviderTimeout,
            None,
            1,
        )
        .is_err()
    );
    assert!(
        RefreshIssueFact::new(
            RefreshIssueKind::Metadata,
            RefreshIssueReason::ProviderInvalidResponse,
            Some(ProviderId::GameTdb),
            1,
        )
        .is_ok()
    );
}

#[test]
fn refresh_issue_fact_rejects_zero_and_unrepresentable_occurrences() {
    assert!(
        RefreshIssueFact::new(
            RefreshIssueKind::Content,
            RefreshIssueReason::ContentUnavailable,
            None,
            0,
        )
        .is_err()
    );
    assert!(
        RefreshIssueFact::new(
            RefreshIssueKind::Content,
            RefreshIssueReason::ContentUnavailable,
            None,
            u64::MAX,
        )
        .is_err()
    );
    let fact = content_fact(RefreshIssueReason::ContentUnavailable, i64::MAX as u64);
    assert_eq!(fact.kind(), RefreshIssueKind::Content);
    assert_eq!(fact.reason(), RefreshIssueReason::ContentUnavailable);
    assert_eq!(fact.provider_id(), None);
    assert_eq!(fact.occurrences(), i64::MAX as u64);
}

#[test]
fn refresh_issue_fact_requires_provider_attribution_matching_its_reason() {
    // A provider-owned failure always names the provider session that was
    // asked, so a providerless provider reason cannot be represented.
    assert!(
        RefreshIssueFact::new(
            RefreshIssueKind::Metadata,
            RefreshIssueReason::ProviderUnavailable,
            None,
            1,
        )
        .is_err(),
        "a provider reason must carry the provider it belongs to"
    );
    // Local and composed-scope reasons are not provider-owned, so attributing
    // them to a provider would invent detail the backend never observed.
    assert!(
        RefreshIssueFact::new(
            RefreshIssueKind::Content,
            RefreshIssueReason::ContentUnavailable,
            Some(ProviderId::GameTdb),
            1,
        )
        .is_err(),
        "a local content reason must not name a provider"
    );
    assert!(
        RefreshIssueFact::new(
            RefreshIssueKind::Scope,
            RefreshIssueReason::ScopeRootScanFailed,
            Some(ProviderId::Playmatch),
            1,
        )
        .is_err(),
        "a composed-scope reason must not name a provider"
    );
    assert!(
        RefreshIssueFact::new(
            RefreshIssueKind::ArtworkDownload,
            RefreshIssueReason::ProviderTimeout,
            Some(ProviderId::SteamGridDb),
            1,
        )
        .is_ok()
    );
}

#[test]
fn refresh_issue_taxonomy_cannot_exceed_the_durable_fact_bound() {
    // Enumerating every representable identity proves the durable bound is
    // unreachable rather than resting on an asserted constant.
    let providers = [
        None,
        Some(ProviderId::Playmatch),
        Some(ProviderId::GameTdb),
        Some(ProviderId::SteamGridDb),
    ];
    let mut identities = std::collections::BTreeSet::new();
    for kind in ALL_KINDS {
        for reason in ALL_REASONS {
            for provider in providers {
                if RefreshIssueFact::new(kind, reason, provider, 1).is_ok() {
                    identities.insert((kind, reason, provider));
                }
            }
        }
    }
    assert_eq!(identities.len(), 113);
    assert!(identities.len() <= RefreshIssueSummary::MAX_FACTS);
}

#[test]
fn refresh_issue_summary_requires_strictly_ascending_identity() {
    let unavailable = content_fact(RefreshIssueReason::ContentUnavailable, 1);
    let changed = content_fact(RefreshIssueReason::ContentChangedDuringRefresh, 1);
    // ContentUnavailable sorts before ContentChangedDuringRefresh.
    assert!(
        RefreshIssueSummary::from_facts(vec![changed, unavailable]).is_err(),
        "descending identity must be rejected"
    );
    assert!(
        RefreshIssueSummary::from_facts(vec![unavailable, unavailable]).is_err(),
        "duplicate identity must be rejected"
    );
    let summary = RefreshIssueSummary::from_facts(vec![unavailable, changed]).expect("ordered");
    assert_eq!(summary.issue_count(), 2);
    assert_eq!(summary.facts().len(), 2);
}

#[test]
fn refresh_issue_summary_rejects_fact_count_above_the_durable_bound() {
    let fact = content_fact(RefreshIssueReason::ContentUnavailable, 1);
    let facts = vec![fact; RefreshIssueSummary::MAX_FACTS + 1];
    assert!(RefreshIssueSummary::from_facts(facts).is_err());
}

#[test]
fn refresh_issue_summary_rejects_occurrence_overflow_without_wrapping() {
    let saturated = content_fact(RefreshIssueReason::ContentUnavailable, i64::MAX as u64);
    let other = content_fact(
        RefreshIssueReason::ContentChangedDuringRefresh,
        i64::MAX as u64,
    );
    let third = content_fact(
        RefreshIssueReason::ContentMalformedOrUnsupported,
        i64::MAX as u64,
    );
    let facts = vec![other, saturated, third];
    assert!(
        RefreshIssueSummary::from_facts(facts).is_err(),
        "a total that cannot be represented must be rejected instead of wrapping"
    );
}

#[test]
fn refresh_issue_accumulator_aggregates_identical_identity() {
    let mut accumulator = RefreshIssueAccumulator::new();
    accumulator
        .record(
            RefreshIssueKind::Metadata,
            RefreshIssueReason::ProviderUnavailable,
            Some(ProviderId::GameTdb),
        )
        .expect("first occurrence");
    accumulator
        .record(
            RefreshIssueKind::Metadata,
            RefreshIssueReason::ProviderUnavailable,
            Some(ProviderId::GameTdb),
        )
        .expect("second occurrence");
    let summary = accumulator.finish().expect("summary");
    assert_eq!(summary.issue_count(), 2);
    assert_eq!(summary.facts().len(), 1);
    assert_eq!(summary.facts()[0].occurrences(), 2);
    assert_eq!(summary.facts()[0].provider_id(), Some(ProviderId::GameTdb));
}

#[test]
fn refresh_issue_accumulator_keeps_different_reasons_and_providers_distinct() {
    let mut accumulator = RefreshIssueAccumulator::new();
    accumulator
        .record(
            RefreshIssueKind::Matching,
            RefreshIssueReason::ProviderUnavailable,
            Some(ProviderId::GameTdb),
        )
        .expect("unavailable");
    accumulator
        .record(
            RefreshIssueKind::Matching,
            RefreshIssueReason::ProviderRateLimited,
            Some(ProviderId::GameTdb),
        )
        .expect("rate limited");
    accumulator
        .record(
            RefreshIssueKind::Matching,
            RefreshIssueReason::ProviderUnavailable,
            Some(ProviderId::Playmatch),
        )
        .expect("other provider");
    let summary = accumulator.finish().expect("summary");
    assert_eq!(summary.issue_count(), 3);
    let identities: Vec<_> = summary
        .facts()
        .iter()
        .map(|fact| (fact.reason(), fact.provider_id()))
        .collect();
    assert_eq!(
        identities,
        vec![
            (
                RefreshIssueReason::ProviderRateLimited,
                Some(ProviderId::GameTdb)
            ),
            (
                RefreshIssueReason::ProviderUnavailable,
                Some(ProviderId::Playmatch)
            ),
            (
                RefreshIssueReason::ProviderUnavailable,
                Some(ProviderId::GameTdb)
            ),
        ],
        "same category and provider with different reasons must stay distinct"
    );
}

#[test]
fn refresh_issue_accumulator_orders_identically_regardless_of_recording_order() {
    let record_all = |order: &[RefreshIssueReason]| {
        let mut accumulator = RefreshIssueAccumulator::new();
        for reason in order {
            accumulator
                .record(RefreshIssueKind::Content, *reason, None)
                .expect("content occurrence");
        }
        accumulator.finish().expect("summary")
    };
    let forward = record_all(&[
        RefreshIssueReason::ContentUnavailable,
        RefreshIssueReason::ContentGroupingFailed,
        RefreshIssueReason::ContentMalformedOrUnsupported,
    ]);
    let reverse = record_all(&[
        RefreshIssueReason::ContentMalformedOrUnsupported,
        RefreshIssueReason::ContentGroupingFailed,
        RefreshIssueReason::ContentUnavailable,
    ]);
    assert_eq!(forward, reverse);
    let reasons: Vec<_> = forward.facts().iter().map(|fact| fact.reason()).collect();
    assert_eq!(
        reasons,
        vec![
            RefreshIssueReason::ContentUnavailable,
            RefreshIssueReason::ContentMalformedOrUnsupported,
            RefreshIssueReason::ContentGroupingFailed,
        ]
    );
}

#[test]
fn refresh_issue_accumulator_merges_composed_roots_without_duplicating_facts() {
    let mut first = RefreshIssueAccumulator::new();
    first
        .record(
            RefreshIssueKind::Scope,
            RefreshIssueReason::ScopeRootScanFailed,
            None,
        )
        .expect("first root");
    let mut second = RefreshIssueAccumulator::new();
    second
        .record(
            RefreshIssueKind::Scope,
            RefreshIssueReason::ScopeRootScanFailed,
            None,
        )
        .expect("second root");
    second
        .record_count(
            RefreshIssueKind::Scope,
            RefreshIssueReason::ScopeRootNotAdmitted,
            None,
            3,
        )
        .expect("three excluded roots");
    first.merge(&second).expect("merge");
    let summary = first.finish().expect("summary");
    assert_eq!(summary.issue_count(), 5);
    assert_eq!(summary.facts().len(), 2);
    assert_eq!(
        summary.facts()[0].reason(),
        RefreshIssueReason::ScopeRootNotAdmitted
    );
    assert_eq!(summary.facts()[0].occurrences(), 3);
    assert_eq!(summary.facts()[1].occurrences(), 2);
}

#[test]
fn refresh_issue_accumulator_rejects_overflow_without_saturating() {
    let mut accumulator = RefreshIssueAccumulator::new();
    accumulator
        .record_count(
            RefreshIssueKind::Content,
            RefreshIssueReason::ContentUnavailable,
            None,
            i64::MAX as u64,
        )
        .expect("bounded occurrence");
    assert!(
        accumulator
            .record(
                RefreshIssueKind::Content,
                RefreshIssueReason::ContentUnavailable,
                None,
            )
            .is_err(),
        "an occurrence the durable domain cannot hold must be rejected"
    );
    assert_eq!(
        accumulator.issue_count().expect("checked total"),
        i64::MAX as u64,
        "a rejected occurrence must not wrap or saturate the recorded total"
    );
    assert!(
        accumulator
            .record_count(
                RefreshIssueKind::Content,
                RefreshIssueReason::ContentUnavailable,
                None,
                0,
            )
            .is_err()
    );
    assert!(
        accumulator
            .record_count(
                RefreshIssueKind::Content,
                RefreshIssueReason::ContentUnavailable,
                None,
                u64::MAX,
            )
            .is_err()
    );
}

#[test]
fn hydration_provider_failures_map_to_typed_refresh_reasons() {
    let cases = [
        (
            HydrationProviderError::AuthenticationFailed,
            RefreshIssueReason::ProviderAuthenticationFailed,
        ),
        (
            HydrationProviderError::AuthorizationFailed,
            RefreshIssueReason::ProviderAuthorizationFailed,
        ),
        (
            HydrationProviderError::Misconfigured,
            RefreshIssueReason::ProviderMisconfigured,
        ),
        (
            HydrationProviderError::RateLimited,
            RefreshIssueReason::ProviderRateLimited,
        ),
        (
            HydrationProviderError::Timeout,
            RefreshIssueReason::ProviderTimeout,
        ),
        (
            HydrationProviderError::Unavailable,
            RefreshIssueReason::ProviderUnavailable,
        ),
        (
            HydrationProviderError::InvalidResponse,
            RefreshIssueReason::ProviderInvalidResponse,
        ),
        (
            HydrationProviderError::UnsupportedCapability,
            RefreshIssueReason::ProviderUnsupportedCapability,
        ),
    ];
    for kind in [
        HydrationIssueKind::Matching,
        HydrationIssueKind::Metadata,
        HydrationIssueKind::ArtworkDiscovery,
        HydrationIssueKind::ArtworkDownload,
    ] {
        for (error, reason) in cases {
            let fact = RefreshIssueFact::from_hydration_parts(
                kind,
                HydrationIssueSource::Provider(error),
                Some(ProviderId::GameTdb),
            )
            .expect("provider fact");
            assert_eq!(fact.reason(), reason);
            assert_eq!(fact.provider_id(), Some(ProviderId::GameTdb));
            assert_eq!(fact.occurrences(), 1);
        }
    }
}

#[test]
fn hydration_asset_store_failures_map_to_typed_refresh_reasons() {
    let cases = [
        (
            ArtworkAssetStoreError::TooLarge,
            RefreshIssueReason::ArtworkAssetTooLarge,
        ),
        (
            ArtworkAssetStoreError::InvalidImage,
            RefreshIssueReason::ArtworkAssetInvalidImage,
        ),
        (
            ArtworkAssetStoreError::DimensionsTooLarge,
            RefreshIssueReason::ArtworkAssetDimensionsTooLarge,
        ),
        (
            ArtworkAssetStoreError::Unavailable,
            RefreshIssueReason::ArtworkAssetStoreUnavailable,
        ),
    ];
    for (error, reason) in cases {
        let fact = RefreshIssueFact::from_hydration_parts(
            HydrationIssueKind::AssetStore,
            HydrationIssueSource::AssetStore(error),
            None,
        )
        .expect("asset store fact");
        assert_eq!(fact.kind(), RefreshIssueKind::AssetStore);
        assert_eq!(fact.reason(), reason);
        assert_eq!(fact.provider_id(), None);
    }
}

#[test]
fn refresh_issue_summary_empty_reports_zero_issues_and_no_facts() {
    let summary = RefreshIssueSummary::empty();
    assert_eq!(summary.issue_count(), 0);
    assert!(summary.facts().is_empty());
    assert_eq!(
        RefreshIssueSummary::from_facts(Vec::new()).expect("empty summary"),
        summary
    );
}
