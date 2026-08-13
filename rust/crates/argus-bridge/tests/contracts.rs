use argus_application::{ApplicationError, ErrorCode, SafeContext, TraceId};
use argus_bridge::{
    AppearanceSettingsDto, BRIDGE_CONTRACT_MAJOR, BridgeResult, RuntimeEventDto,
    RuntimeEventPayloadDto, RuntimeLifecycleDto, ThemeModeDto, application_error_dto,
    retry_startup, runtime_event_dto, runtime_state_dto,
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
