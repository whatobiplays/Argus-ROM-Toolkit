//! Phase 000 explicit recovery coordination for failed runtime generations.

use argus_application::{ApplicationError, ErrorCode, OperationContext};

use crate::{
    ApplicationHost, KernelBootstrap, RecoveryActionKind, RuntimeEventPayload, RuntimeInstanceId,
    RuntimeLifecycle, RuntimeState,
};

/// Sole explicit recovery orchestrator for failed runtime generations.
pub struct RecoveryCoordinator;

impl RecoveryCoordinator {
    /// Retires the failed generation and starts a completely fresh one.
    pub fn retry_startup(
        host: &ApplicationHost,
        expected_runtime_instance_id: RuntimeInstanceId,
        context: &OperationContext,
    ) -> Result<RuntimeState, ApplicationError> {
        Self::require_action(
            host,
            expected_runtime_instance_id,
            RecoveryActionKind::RetryStartup,
            context,
        )?;
        let kernel = Self::retire(host, expected_runtime_instance_id, context)?;
        if let Some(kernel) = kernel
            && kernel.shutdown().is_err()
        {
            return Err(runtime_recovery_error(
                ErrorCode::InternalUnexpected,
                context.trace_id(),
            ));
        }
        host.install_fresh_generation_with_context(expected_runtime_instance_id, context)
    }

    /// Performs the targeted appearance reset then starts a fresh generation.
    pub fn reset_appearance_settings(
        host: &ApplicationHost,
        expected_runtime_instance_id: RuntimeInstanceId,
        context: &OperationContext,
    ) -> Result<RuntimeState, ApplicationError> {
        Self::require_action(
            host,
            expected_runtime_instance_id,
            RecoveryActionKind::ResetAppearanceSettings,
            context,
        )?;
        Self::require_isolated_appearance_failure(host, context)?;
        let recovery_context = {
            let generation = host.lock_generation_with_context(context)?;
            host.validate_failed_generation_with_context(
                &generation,
                expected_runtime_instance_id,
                context,
            )?;
            generation.recovery_context.clone()
        };
        {
            let Some(recovery_context) = recovery_context else {
                return Err(runtime_recovery_error(
                    ErrorCode::RuntimeStartupFailed,
                    context.trace_id(),
                ));
            };
            let Some(capability) = recovery_context.appearance_reset.as_ref() else {
                return Err(runtime_recovery_error(
                    ErrorCode::RuntimeStartupFailed,
                    context.trace_id(),
                ));
            };
            capability.reset(context)?;
        }
        Self::retire(host, expected_runtime_instance_id, context)?;
        host.install_fresh_generation_with_context(expected_runtime_instance_id, context)
    }

    /// Retires the failed generation through `ShuttingDown` to `Stopped`.
    pub fn exit_failed_runtime(
        host: &ApplicationHost,
        expected_runtime_instance_id: RuntimeInstanceId,
        context: &OperationContext,
    ) -> Result<RuntimeState, ApplicationError> {
        Self::require_action(
            host,
            expected_runtime_instance_id,
            RecoveryActionKind::Exit,
            context,
        )?;
        let kernel = Self::retire(host, expected_runtime_instance_id, context)?;
        if let Some(kernel) = kernel
            && kernel.shutdown().is_err()
        {
            return Err(runtime_recovery_error(
                ErrorCode::InternalUnexpected,
                context.trace_id(),
            ));
        }
        Ok(host.current_state())
    }

    fn require_action(
        host: &ApplicationHost,
        expected_runtime_instance_id: RuntimeInstanceId,
        kind: RecoveryActionKind,
        context: &OperationContext,
    ) -> Result<(), ApplicationError> {
        let generation = host.lock_generation_with_context(context)?;
        host.validate_failed_generation_with_context(
            &generation,
            expected_runtime_instance_id,
            context,
        )?;
        let failure = generation.state.startup_failure().ok_or_else(|| {
            runtime_recovery_error(ErrorCode::RuntimeStartupFailed, context.trace_id())
        })?;
        if !failure
            .recovery_actions
            .iter()
            .any(|action| action.kind == kind)
        {
            return Err(runtime_recovery_error(
                ErrorCode::RuntimeStartupFailed,
                context.trace_id(),
            ));
        }
        Ok(())
    }

    fn require_isolated_appearance_failure(
        host: &ApplicationHost,
        context: &OperationContext,
    ) -> Result<(), ApplicationError> {
        let generation = host.lock_generation_with_context(context)?;
        let failure = generation.state.startup_failure().ok_or_else(|| {
            runtime_recovery_error(ErrorCode::RuntimeStartupFailed, context.trace_id())
        })?;
        if failure.phase != crate::StartupPhase::SettingsInitialization
            || failure.error.code != ErrorCode::ConfigurationPersistedSettingsInvalid
        {
            return Err(runtime_recovery_error(
                ErrorCode::RuntimeStartupFailed,
                context.trace_id(),
            ));
        }
        Ok(())
    }

    fn retire(
        host: &ApplicationHost,
        expected_runtime_instance_id: RuntimeInstanceId,
        context: &OperationContext,
    ) -> Result<Option<KernelBootstrap>, ApplicationError> {
        let kernel = {
            let mut generation = host.lock_generation_with_context(context)?;
            host.validate_failed_generation_with_context(
                &generation,
                expected_runtime_instance_id,
                context,
            )?;
            generation.state = RuntimeState::ShuttingDown {
                runtime_instance_id: generation.id,
            };
            host.publish_outward(RuntimeEventPayload::RuntimeStateChanged {
                lifecycle: RuntimeLifecycle::ShuttingDown,
            });
            generation.state = RuntimeState::Stopped {
                runtime_instance_id: generation.id,
            };
            host.publish_outward(RuntimeEventPayload::RuntimeStateChanged {
                lifecycle: RuntimeLifecycle::Stopped,
            });
            generation.events.close();
            host.clear_active_event();
            generation.take_kernel()
        };
        Ok(kernel)
    }
}

fn runtime_recovery_error(
    code: ErrorCode,
    trace_id: argus_application::TraceId,
) -> ApplicationError {
    ApplicationError::from_code(code, trace_id, argus_application::SafeContext::new())
        .expect("recovery error uses an allowlisted empty context")
}
