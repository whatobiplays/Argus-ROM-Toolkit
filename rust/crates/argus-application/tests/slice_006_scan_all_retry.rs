//! Slice 006 application-contract tests for Scan All retry semantics.

use argus_application::{
    ErrorCode, FailureRole, JobRunId, LibraryRootId, LibraryScanTarget,
    LibraryScanTargetEligibility, LibraryScanTargetExclusionReason, LibraryScanTargetKind,
    OperationHandle, RetryJobAdmissionResult, RetryJobResult, SafeContextField, SafeContextValue,
    ScanRunId, TechnicalClass, TraceId, evaluate_retry_eligibility_with_trace,
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

#[test]
fn scan_all_retry_eligibility_carries_the_bounded_invalid_configuration_error() {
    let trace_id = TraceId::try_from(7).expect("trace id");
    let invalid = (
        requested_target(root("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")),
        LibraryScanTargetEligibility {
            configured: true,
            configuration_valid: false,
            active_owner: None,
        },
    );
    let evaluation = evaluate_retry_eligibility_with_trace(
        Some(trace_id),
        argus_application::JobRunState::Failed,
        false,
        &[invalid],
    );
    assert!(!evaluation.can_retry());
    assert_eq!(
        evaluation.exclusions()[0].reason(),
        LibraryScanTargetExclusionReason::InvalidConfiguration
    );
    let error = evaluation.exclusions()[0]
        .application_error()
        .expect("bounded error");
    assert_eq!(error.code, ErrorCode::ConfigurationInvalid);
    assert_eq!(error.message_key.as_str(), "errors.configuration.invalid");
    assert_eq!(
        error.safe_context.get(&SafeContextField::TechnicalClass),
        Some(&SafeContextValue::TechnicalClass(
            TechnicalClass::ConfigurationInvalid
        ))
    );
    assert_eq!(
        error.safe_context.get(&SafeContextField::FailureRole),
        Some(&SafeContextValue::FailureRole(FailureRole::Primary))
    );
}

#[test]
fn scan_all_retry_admission_payload_carries_the_job_and_exclusion_count() {
    let job_run_id = job("11111111111111111111111111111111");
    let root_id = root("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    let plan = argus_application::LibraryScanExecutionPlan::new(
        root_id,
        job_run_id,
        scan("22222222222222222222222222222222"),
        argus_application::RootLocator::from_provider("/library/Games".to_owned()),
        "Games",
        "/library/Games",
        1,
        1,
        1,
        1_000,
    );
    let admitted_job = argus_application::AdmittedLibraryScanJob::new(job_run_id, vec![plan]);
    let result = RetryJobAdmissionResult::admitted_scan_all(
        OperationHandle::new(job_run_id, argus_application::OPERATION_TYPE_LIBRARY_SCAN),
        admitted_job,
        2,
    );
    assert!(matches!(result.outcome(), RetryJobResult::Admitted(_)));
    assert_eq!(result.admitted_job_exclusion_count(), 2);
    assert_eq!(result.admitted_job().expect("job").job_run_id(), job_run_id);
    assert!(result.admitted_scan().is_none());
}
