use argus_application::{ApplicationError, ErrorCode, SafeContext, TraceId};
use argus_application::{
    LibraryRootId, LibraryScanAdmissionExclusion, LibraryScanAllRequestIdentity, OperationHandle,
    StartLibraryScanAllResult,
};
use argus_bridge::{
    AppearanceSettingsDto, BRIDGE_CONTRACT_MAJOR, BridgeResult, RuntimeEventDto,
    RuntimeEventPayloadDto, RuntimeLifecycleDto, ThemeModeDto, application_error_dto,
    library_scan_all_request_resolution_dto, parse_scan_all_request_identity, retry_startup,
    runtime_event_dto, runtime_state_dto, start_library_scan_all_result_dto,
};
use argus_runtime::{
    RecoveryAction, RecoveryActionKind, RuntimeEvent, RuntimeEventPayload, RuntimeInstanceId,
    RuntimeLifecycle, RuntimeState, StartupFailure, StartupPhase,
};

#[test]
fn application_error_projection_preserves_stable_fields() {
    let error = ApplicationError::from_code(
        ErrorCode::RuntimeStaleInstance,
        TraceId::try_from([7; 16]).expect("trace"),
        SafeContext::new(),
    )
    .expect("error");
    let dto = application_error_dto(&error);
    assert_eq!(dto.code, "ARGUS.V1.RUNTIME.STALE_INSTANCE");
    assert_eq!(dto.category, "runtime");
    assert_eq!(dto.severity, "Warning");
    assert_eq!(dto.recoverability, "UserAction");
    assert_eq!(dto.retry_policy, "Never");
    assert_eq!(dto.trace_id, "07070707070707070707070707070707");
}

#[test]
fn scan_all_result_dto_preserves_admitted_roots_exclusions_and_bounded_error() {
    let trace = TraceId::try_from([9; 16]).expect("trace");
    let invalid = LibraryScanAdmissionExclusion::invalid_configuration(
        LibraryRootId::try_from("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb").expect("root"),
        ApplicationError::from_code(ErrorCode::ConfigurationInvalid, trace, SafeContext::new())
            .expect("error"),
    );
    let admitted = StartLibraryScanAllResult::Admitted {
        operation_handle: OperationHandle::new(
            argus_application::JobRunId::from_bytes([1; 16]).expect("job"),
            argus_application::OPERATION_TYPE_LIBRARY_SCAN,
        ),
        admitted_roots: vec![
            LibraryRootId::try_from("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa").expect("root"),
        ],
        exclusions: vec![invalid.clone()],
    };
    let dto = start_library_scan_all_result_dto(&admitted);
    let argus_bridge::StartLibraryScanAllResultDto::Admitted {
        operation_handle,
        admitted_roots,
        exclusions,
    } = dto
    else {
        panic!("expected admitted DTO");
    };
    assert_eq!(
        operation_handle.job_run_id,
        "01010101010101010101010101010101"
    );
    assert_eq!(
        admitted_roots,
        vec!["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_owned()]
    );
    assert_eq!(exclusions.len(), 1);
    assert_eq!(exclusions[0].reason, "invalid_configuration");
    assert_eq!(
        exclusions[0]
            .application_error
            .as_ref()
            .expect("error")
            .code,
        "ARGUS.V1.CONFIGURATION.INVALID"
    );

    let nothing = StartLibraryScanAllResult::NothingEligible {
        exclusions: vec![invalid],
    };
    let nothing_dto = start_library_scan_all_result_dto(&nothing);
    assert!(matches!(
        nothing_dto,
        argus_bridge::StartLibraryScanAllResultDto::NothingEligible { .. }
    ));
}

#[test]
fn scan_all_request_resolution_dto_maps_admission_and_no_admission_proof() {
    let admitted = Some(StartLibraryScanAllResult::Admitted {
        operation_handle: OperationHandle::new(
            argus_application::JobRunId::from_bytes([2; 16]).expect("job"),
            argus_application::OPERATION_TYPE_LIBRARY_SCAN,
        ),
        admitted_roots: vec![
            LibraryRootId::try_from("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa").expect("root"),
        ],
        exclusions: vec![],
    });
    assert!(matches!(
        library_scan_all_request_resolution_dto(admitted),
        argus_bridge::LibraryScanAllRequestResolutionDto::Admitted { .. }
    ));
    assert_eq!(
        library_scan_all_request_resolution_dto(None),
        argus_bridge::LibraryScanAllRequestResolutionDto::NothingAdmitted
    );
}

#[test]
fn scan_all_request_identity_parses_valid_and_rejects_invalid_input() {
    let trace = TraceId::try_from([3; 16]).expect("trace");
    let parsed = parse_scan_all_request_identity("request-1.ab_c", trace).expect("valid");
    assert_eq!(
        parsed,
        LibraryScanAllRequestIdentity::try_from("request-1.ab_c").expect("identity")
    );
    let invalid = parse_scan_all_request_identity("has spaces", trace).expect_err("invalid");
    assert_eq!(invalid.code, "ARGUS.V1.VALIDATION.INVALID_ARGUMENT");
    let empty = parse_scan_all_request_identity("", trace).expect_err("empty");
    assert_eq!(empty.code, "ARGUS.V1.VALIDATION.INVALID_ARGUMENT");
}

#[test]
fn runtime_snapshot_has_one_lifecycle_and_failure_authority() {
    let id = RuntimeInstanceId::new();
    let state = RuntimeState::StartupFailed {
        runtime_instance_id: id,
        failure: StartupFailure {
            phase: StartupPhase::SettingsInitialization,
            error: ApplicationError::from_code(
                ErrorCode::ConfigurationPersistedSettingsInvalid,
                TraceId::try_from([8; 16]).expect("trace"),
                SafeContext::new(),
            )
            .expect("error"),
            recovery_actions: vec![RecoveryAction {
                kind: RecoveryActionKind::RetryStartup,
            }],
            diagnostics_available: true,
            data_directory_available: true,
        },
    };
    let dto = runtime_state_dto(&state);
    assert_eq!(dto.lifecycle_state, RuntimeLifecycleDto::StartupFailed);
    assert!(dto.startup_failure.is_some());
    assert_eq!(dto.runtime_instance_id.len(), 32);
}

#[test]
fn appearance_settings_and_events_use_canonical_typed_dtos() {
    let settings = AppearanceSettingsDto {
        theme_mode: ThemeModeDto::Dark,
    };
    assert_eq!(settings.theme_mode, ThemeModeDto::Dark);

    let event = RuntimeEvent {
        runtime_instance_id: RuntimeInstanceId::new(),
        sequence: 4,
        occurred_at_ms: 10,
        payload: RuntimeEventPayload::AppearanceSettingsChanged,
    };
    let dto = runtime_event_dto(&event);
    assert_eq!(dto.sequence, 4);
    assert_eq!(
        dto.payload,
        RuntimeEventPayloadDto::AppearanceSettingsChanged
    );
}

#[test]
fn event_stream_items_are_payload_dtos_not_bridge_results() {
    fn accepts_event(_: RuntimeEventDto) {}
    let _result_type: Option<BridgeResult<RuntimeEventDto>> = None;
    let _ = accepts_event;
}

#[test]
fn bridge_contract_major_is_stable_at_one() {
    assert_eq!(BRIDGE_CONTRACT_MAJOR, 1);
}

#[test]
fn generation_bound_recovery_requests_reject_invalid_identity() {
    let error = retry_startup("not-hex".to_owned()).expect_err("invalid identity");
    assert_eq!(error.code, "ARGUS.V1.VALIDATION.INVALID_ARGUMENT");
}

#[test]
fn malformed_runtime_id_uses_request_trace_and_requests_differ() {
    let first = retry_startup("not-hex".to_owned()).expect_err("first invalid identity");
    let second = retry_startup("not-hex".to_owned()).expect_err("second invalid identity");
    assert_eq!(first.code, "ARGUS.V1.VALIDATION.INVALID_ARGUMENT");
    assert_ne!(first.trace_id, second.trace_id);
    assert_ne!(first.trace_id, "00000000000000000000000000000000");
}

#[test]
fn event_payload_families_map_without_loss() {
    let id = RuntimeInstanceId::new();
    let state_changed = runtime_event_dto(&RuntimeEvent {
        runtime_instance_id: id,
        sequence: 3,
        occurred_at_ms: 11,
        payload: RuntimeEventPayload::RuntimeStateChanged {
            lifecycle: RuntimeLifecycle::Ready,
        },
    });
    assert!(matches!(
        state_changed.payload,
        RuntimeEventPayloadDto::RuntimeStateChanged { .. }
    ));

    let startup_failed = runtime_event_dto(&RuntimeEvent {
        runtime_instance_id: id,
        sequence: 4,
        occurred_at_ms: 12,
        payload: RuntimeEventPayload::StartupFailed {
            phase: StartupPhase::ReadinessValidation,
        },
    });
    assert!(matches!(
        startup_failed.payload,
        RuntimeEventPayloadDto::StartupFailed { .. }
    ));
}
