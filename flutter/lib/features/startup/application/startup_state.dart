import 'package:argus/core/client/client.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'startup_state.freezed.dart';

/// Immutable state of one runtime-changing recovery operation.
@freezed
sealed class RecoveryOperationState with _$RecoveryOperationState {
  const factory RecoveryOperationState.idle() = RecoveryOperationStateIdle;

  const factory RecoveryOperationState.running() =
      RecoveryOperationStateRunning;

  const factory RecoveryOperationState.failed(ClientFailure error) =
      RecoveryOperationStateFailed;
}

/// Immutable state of one diagnostic-export operation.
@freezed
sealed class ExportOperationState with _$ExportOperationState {
  const factory ExportOperationState.idle() = ExportOperationStateIdle;

  const factory ExportOperationState.running() = ExportOperationStateRunning;

  const factory ExportOperationState.succeeded(DiagnosticsExport result) =
      ExportOperationStateSucceeded;

  const factory ExportOperationState.failed(ClientFailure error) =
      ExportOperationStateFailed;
}

/// Immutable state of lazy technical-details loading.
@freezed
sealed class TechnicalDetailsOperationState
    with _$TechnicalDetailsOperationState {
  const factory TechnicalDetailsOperationState.idle() =
      TechnicalDetailsOperationStateIdle;

  const factory TechnicalDetailsOperationState.loading() =
      TechnicalDetailsOperationStateLoading;

  const factory TechnicalDetailsOperationState.loaded(
    TechnicalDetails details,
  ) = TechnicalDetailsOperationStateLoaded;

  const factory TechnicalDetailsOperationState.failed(ClientFailure error) =
      TechnicalDetailsOperationStateFailed;
}

/// Immutable state of the advertised open-data-directory operation.
@freezed
sealed class OpenDirectoryOperationState with _$OpenDirectoryOperationState {
  const factory OpenDirectoryOperationState.idle() =
      OpenDirectoryOperationStateIdle;

  const factory OpenDirectoryOperationState.running() =
      OpenDirectoryOperationStateRunning;

  const factory OpenDirectoryOperationState.failed(ClientFailure error) =
      OpenDirectoryOperationStateFailed;
}

/// Immutable state of authoritative runtime reconciliation.
@freezed
sealed class ReconciliationOperationState with _$ReconciliationOperationState {
  const factory ReconciliationOperationState.idle() =
      ReconciliationOperationStateIdle;

  const factory ReconciliationOperationState.running() =
      ReconciliationOperationStateRunning;

  const factory ReconciliationOperationState.failed(ClientFailure error) =
      ReconciliationOperationStateFailed;
}

/// Last-known runtime context retained only when authority is unavailable.
@freezed
sealed class StartupRuntimeContext with _$StartupRuntimeContext {
  const factory StartupRuntimeContext({
    required RuntimeInstanceId runtimeInstanceId,
    required RuntimeLifecycle lifecycle,
    StartupPhase? phase,
  }) = _StartupRuntimeContext;
}

/// Explicit pre-ready startup state machine owned by the startup controller.
///
/// The outer `AsyncValue` answers whether a usable runtime contract was ever
/// established; backend lifecycle states live inside this union so a
/// transported `StartupFailed` remains loaded inspectable data.
@freezed
sealed class StartupState with _$StartupState {
  const factory StartupState.uninitialized({
    required RuntimeInstanceId runtimeInstanceId,
  }) = StartupStateUninitialized;

  const factory StartupState.starting({
    required RuntimeInstanceId runtimeInstanceId,
    StartupPhase? phase,
  }) = StartupStateStarting;

  const factory StartupState.ready({
    required RuntimeInstanceId runtimeInstanceId,
  }) = StartupStateReady;

  const factory StartupState.startupFailed({
    required RuntimeInstanceId runtimeInstanceId,
    required StartupFailure failure,
    required RecoveryOperationState recoveryOperation,
    required ExportOperationState exportOperation,
    required TechnicalDetailsOperationState technicalDetails,
    required OpenDirectoryOperationState openDirectoryOperation,
  }) = StartupStateStartupFailed;

  const factory StartupState.runtimeUnavailable({
    required ClientFailure cause,
    required StartupRuntimeContext? lastKnownRuntime,
    required ReconciliationOperationState reconciliationOperation,
  }) = StartupStateRuntimeUnavailable;

  const factory StartupState.shuttingDown({
    required RuntimeInstanceId runtimeInstanceId,
  }) = StartupStateShuttingDown;

  const factory StartupState.stopped({
    required RuntimeInstanceId runtimeInstanceId,
  }) = StartupStateStopped;
}

/// Returns the runtime identity carried by every state variant, if any.
RuntimeInstanceId? startupRuntimeId(StartupState state) => switch (state) {
  StartupStateUninitialized(:final runtimeInstanceId) => runtimeInstanceId,
  StartupStateStarting(:final runtimeInstanceId) => runtimeInstanceId,
  StartupStateReady(:final runtimeInstanceId) => runtimeInstanceId,
  StartupStateStartupFailed(:final runtimeInstanceId) => runtimeInstanceId,
  StartupStateRuntimeUnavailable() => null,
  StartupStateShuttingDown(:final runtimeInstanceId) => runtimeInstanceId,
  StartupStateStopped(:final runtimeInstanceId) => runtimeInstanceId,
};
