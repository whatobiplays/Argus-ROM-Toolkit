import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'appearance_settings_dependencies.dart';
import 'appearance_settings_state.dart';

part 'appearance_settings_controller.g.dart';

/// One application-lifetime owner of frontend appearance state.
///
/// The outer [AsyncValue] represents whether usable appearance authority
/// exists: loading until the first authoritative read completes, error when
/// that initial read fails, and data with separated confirmed/presented
/// semantics afterwards. A loaded last-known snapshot remains renderable
/// across runtime replacement; only a successful authoritative read changes
/// [AppearanceSettingsState.confirmed].
@Riverpod(keepAlive: true)
class AppearanceSettingsController extends _$AppearanceSettingsController {
  RuntimeInstanceId? _activeRuntimeInstanceId;
  AppearanceSettingsState? _lastLoaded;
  int _readToken = 0;
  bool _readInFlight = false;

  @override
  AsyncValue<AppearanceSettingsState> build() {
    final context = ref.watch(appearanceRuntimeContextProvider);
    // Any context change invalidates older completions and operation flags.
    _readToken++;
    _readInFlight = false;
    _activeRuntimeInstanceId = switch (context) {
      AppearanceRuntimeContextPreReady() => null,
      AppearanceRuntimeContextReady(:final runtimeInstanceId) =>
        runtimeInstanceId,
    };

    // A loaded last-known snapshot remains renderable while a fresh runtime
    // is adopted; only the read completion may change confirmed authority.
    final lastLoaded = _lastLoaded;
    final retained = lastLoaded == null
        ? null
        : AppearanceSettingsState.ready(
            confirmed: lastLoaded.confirmed,
            presented: lastLoaded.confirmed,
            saveOperation: const AppearanceSaveOperation.idle(),
            synchronization: const AppearanceSynchronization.refreshing(),
          );

    // Defer adoption until build completes so the notifier's own state is
    // initialized before it is read or written.
    scheduleMicrotask(() => unawaited(_adoptRuntimeContext(context)));
    return retained == null ? const AsyncLoading() : AsyncData(retained);
  }

  /// Issues a focused authoritative read after a failure or uncertainty.
  ///
  /// Read-only recovery: this never calls [SettingsApi.updateAppearanceSettings].
  Future<void> retryAuthoritativeRead() async {
    final runtimeId = _activeRuntimeInstanceId;
    if (runtimeId == null || _readInFlight) return;

    if (state.hasError) {
      state = const AsyncLoading();
      await _readAuthoritative(runtimeId, token: _readToken);
      return;
    }

    final current = state.value;
    if (current == null) return;
    final refreshing = _withSynchronization(
      current,
      const AppearanceSynchronization.refreshing(),
    );
    _lastLoaded = refreshing;
    state = AsyncData(refreshing);
    await _readAuthoritative(runtimeId, token: _readToken);
  }

  Future<void> _adoptRuntimeContext(AppearanceRuntimeContext context) async {
    final runtimeId = switch (context) {
      AppearanceRuntimeContextPreReady() => null,
      AppearanceRuntimeContextReady(:final runtimeInstanceId) =>
        runtimeInstanceId,
    };

    if (runtimeId != null) {
      await _readAuthoritative(runtimeId, token: _readToken);
    }
  }

  Future<void> _readAuthoritative(
    RuntimeInstanceId runtimeId, {
    required int token,
  }) async {
    if (_readInFlight) return;
    _readInFlight = true;
    final api = ref.read(appearanceSettingsApiProvider);
    try {
      final result = await api.getAppearanceSettings();
      if (token != _readToken || runtimeId != _activeRuntimeInstanceId) return;
      final loaded = AppearanceSettingsState.ready(
        confirmed: result,
        presented: result,
        saveOperation: const AppearanceSaveOperation.idle(),
        synchronization: const AppearanceSynchronization.synchronized(),
      );
      _lastLoaded = loaded;
      state = AsyncData(loaded);
    } catch (error, stackTrace) {
      if (token != _readToken || runtimeId != _activeRuntimeInstanceId) return;
      final failure = _asClientFailure(error);
      final current = _lastLoaded;
      if (current == null) {
        state = AsyncError(failure, stackTrace);
      } else {
        final uncertain = AppearanceSettingsState.ready(
          confirmed: current.confirmed,
          presented: current.confirmed,
          saveOperation: current.saveOperation,
          synchronization: AppearanceSynchronization.uncertain(
            failure: failure,
          ),
        );
        _lastLoaded = uncertain;
        state = AsyncData(uncertain);
      }
    } finally {
      if (token == _readToken) {
        _readInFlight = false;
      }
    }
  }

  AppearanceSettingsState _withSynchronization(
    AppearanceSettingsState state,
    AppearanceSynchronization synchronization,
  ) {
    final ready = state as AppearanceSettingsStateReady;
    return AppearanceSettingsState.ready(
      confirmed: ready.confirmed,
      presented: ready.presented,
      saveOperation: ready.saveOperation,
      synchronization: synchronization,
    );
  }

  ClientFailure _asClientFailure(Object error) {
    if (error is ClientFailure) return error;
    return TransportFailure('Unexpected appearance failure', cause: error);
  }
}
