import 'package:argus/core/client/client.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'appearance_settings_state.freezed.dart';

/// Typed identity of the runtime generation that owns appearance authority.
///
/// The frontend never treats a submitted mutation or event payload as
/// authority; every confirmed value comes from a successful
/// [SettingsApi.getAppearanceSettings] read scoped to the current runtime.
@freezed
sealed class AppearanceRuntimeContext with _$AppearanceRuntimeContext {
  /// No usable runtime context has been published yet.
  const factory AppearanceRuntimeContext.preReady() =
      AppearanceRuntimeContextPreReady;

  /// A specific runtime generation is current and authoritative.
  const factory AppearanceRuntimeContext.ready({
    required RuntimeInstanceId runtimeInstanceId,
  }) = AppearanceRuntimeContextReady;
}

/// One application-lifetime appearance mutation operation.
///
/// [AppearanceSaveOperationOutcomeUnknown] and
/// [AppearanceSaveOperationCommittedButUnreconciled] are ambiguous outcomes:
/// the frontend never replays them and only a focused read reconciles them.
@freezed
sealed class AppearanceSaveOperation with _$AppearanceSaveOperation {
  /// No mutation is in flight or awaiting reconciliation.
  const factory AppearanceSaveOperation.idle() = AppearanceSaveOperationIdle;

  /// A mutation was admitted and is awaiting its outcome or reconciliation.
  const factory AppearanceSaveOperation.saving({
    required AppearanceSettings requested,
  }) = AppearanceSaveOperationSaving;

  /// The mutation failed definitely at the application boundary.
  const factory AppearanceSaveOperation.failed({
    required ApplicationFailure failure,
  }) = AppearanceSaveOperationFailed;

  /// The mutation outcome is unknown because transport failed.
  const factory AppearanceSaveOperation.outcomeUnknown({
    required TransportFailure failure,
  }) = AppearanceSaveOperationOutcomeUnknown;

  /// The mutation was acknowledged but the confirming read failed.
  const factory AppearanceSaveOperation.committedButUnreconciled({
    required ClientFailure failure,
  }) = AppearanceSaveOperationCommittedButUnreconciled;
}

/// Relationship between frontend appearance state and backend authority.
@freezed
sealed class AppearanceSynchronization with _$AppearanceSynchronization {
  /// The loaded snapshot is current and mutations are admissible.
  const factory AppearanceSynchronization.synchronized() =
      AppearanceSynchronizationSynchronized;

  /// A focused read is in progress or a runtime change invalidated confidence.
  const factory AppearanceSynchronization.refreshing() =
      AppearanceSynchronizationRefreshing;

  /// A focused read failed; the last-known snapshot remains renderable.
  const factory AppearanceSynchronization.uncertain({
    required ClientFailure failure,
  }) = AppearanceSynchronizationUncertain;
}

/// Loaded appearance state separated into confirmed authority and the
/// presented UI state.
///
/// [confirmed] changes only from successful authoritative reads. [presented]
/// may differ only while an explicit local pending selection is displayed.
@freezed
sealed class AppearanceSettingsState with _$AppearanceSettingsState {
  /// A usable appearance snapshot exists.
  const factory AppearanceSettingsState.ready({
    required AppearanceSettings confirmed,
    required AppearanceSettings presented,
    required AppearanceSaveOperation saveOperation,
    required AppearanceSynchronization synchronization,
  }) = AppearanceSettingsStateReady;
}
