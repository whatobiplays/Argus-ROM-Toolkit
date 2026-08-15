//! Slice 005 tests for the one shared retry-eligibility seam consumed by both
//! the Jobs projection (`canRetry`) and Retry admission.

use argus_application::{
    ActiveScanOwnership, JobRunId, JobRunState, LibraryRootId, LibraryScanTarget,
    LibraryScanTargetEligibility, LibraryScanTargetExclusionReason, LibraryScanTargetKind,
    ScanRunId, evaluate_retry_eligibility,
};

fn root(value: &str) -> LibraryRootId {
    LibraryRootId::try_from(value).expect("root id")
}

fn job(value: &str) -> JobRunId {
    JobRunId::try_from(value).expect("job id")
}

fn scan(value: &str) -> ScanRunId {
    ScanRunId::try_from(value).expect("scan id")
}

fn requested_target(root_id: LibraryRootId) -> LibraryScanTarget {
    LibraryScanTarget::new(
        LibraryScanTargetKind::Requested,
        root_id,
        "Games",
        "/library/Games",
        None,
        None,
    )
}

fn eligible() -> LibraryScanTargetEligibility {
    LibraryScanTargetEligibility {
        configured: true,
        configuration_valid: true,
        active_owner: None,
    }
}

#[test]
fn every_retryable_terminal_state_with_an_eligible_target_can_retry() {
    for state in [
        JobRunState::CompletedWithIssues,
        JobRunState::Failed,
        JobRunState::Cancelled,
        JobRunState::Abandoned,
    ] {
        let evaluation = evaluate_retry_eligibility(
            state,
            false,
            &[(
                requested_target(root("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")),
                eligible(),
            )],
        );
        assert!(evaluation.can_retry(), "state {state:?} must be retryable");
        assert!(evaluation.exclusions().is_empty());
    }
}

#[test]
fn clean_completed_active_and_successor_states_are_not_retryable() {
    let target = (
        requested_target(root("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")),
        eligible(),
    );
    assert!(
        !evaluate_retry_eligibility(JobRunState::Completed, false, std::slice::from_ref(&target),)
            .can_retry()
    );
    assert!(
        !evaluate_retry_eligibility(JobRunState::Running, false, std::slice::from_ref(&target),)
            .can_retry()
    );
    assert!(!evaluate_retry_eligibility(JobRunState::Interrupted, false, &[target]).can_retry());
    assert!(
        !evaluate_retry_eligibility(
            JobRunState::Failed,
            true,
            &[(
                requested_target(root("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")),
                eligible()
            )],
        )
        .can_retry()
    );
}

#[test]
fn missing_and_invalid_targets_produce_typed_exclusions_and_no_retry() {
    let missing = (
        requested_target(root("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")),
        LibraryScanTargetEligibility {
            configured: false,
            configuration_valid: false,
            active_owner: None,
        },
    );
    let evaluation = evaluate_retry_eligibility(JobRunState::Failed, false, &[missing]);
    assert!(!evaluation.can_retry());
    assert_eq!(
        evaluation.exclusions()[0].reason(),
        LibraryScanTargetExclusionReason::NoLongerConfigured
    );

    let invalid = (
        requested_target(root("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")),
        LibraryScanTargetEligibility {
            configured: true,
            configuration_valid: false,
            active_owner: None,
        },
    );
    let evaluation = evaluate_retry_eligibility(JobRunState::Failed, false, &[invalid]);
    assert!(!evaluation.can_retry());
    assert_eq!(
        evaluation.exclusions()[0].reason(),
        LibraryScanTargetExclusionReason::InvalidConfiguration
    );
}

#[test]
fn active_ownership_exclusion_carries_the_owning_identities() {
    let target = (
        requested_target(root("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")),
        LibraryScanTargetEligibility {
            configured: true,
            configuration_valid: true,
            active_owner: Some(ActiveScanOwnership::new(
                job("11111111111111111111111111111111"),
                scan("22222222222222222222222222222222"),
                1,
            )),
        },
    );
    let evaluation = evaluate_retry_eligibility(JobRunState::Failed, false, &[target]);
    assert!(!evaluation.can_retry());
    assert_eq!(
        evaluation.exclusions()[0].reason(),
        LibraryScanTargetExclusionReason::AlreadyScanning
    );
    assert_eq!(
        evaluation.exclusions()[0].active_job_run_id(),
        Some(job("11111111111111111111111111111111"))
    );
    assert_eq!(
        evaluation.exclusions()[0].active_scan_run_id(),
        Some(scan("22222222222222222222222222222222"))
    );
}

#[test]
fn mixed_targets_retry_the_eligible_one_and_record_exclusions() {
    let evaluation = evaluate_retry_eligibility(
        JobRunState::Failed,
        false,
        &[
            (
                requested_target(root("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")),
                eligible(),
            ),
            (
                requested_target(root("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")),
                LibraryScanTargetEligibility {
                    configured: false,
                    configuration_valid: false,
                    active_owner: None,
                },
            ),
        ],
    );
    assert!(evaluation.can_retry());
    assert_eq!(evaluation.exclusions().len(), 1);
    assert_eq!(
        evaluation.exclusions()[0].library_root_id(),
        root("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
    );
}
