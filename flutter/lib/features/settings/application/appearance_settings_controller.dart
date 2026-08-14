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
  AppearanceRuntimeContext? _lastRuntimeContext;
  AsyncValue<AppearanceSettingsState>? _lastBuildValue;
  int _readToken = 0;
  bool _readInFlight = false;
  int _mutationToken = 0;
  bool _mutationInFlight = false;
  bool _pendingReconciliationDemand = false;
  int _demandToken = 0;
  StreamSubscription<AppearanceReconciliationDemand>? _demandSubscription;

  @override
  AsyncValue<AppearanceSettingsState> build() {
    ref.onDispose(() {
      _demandToken++;
      _demandSubscription?.cancel();
    });
    // Watching the demand channel keeps the app-level event coordinator's
    // provider chain active. Source replacement retires only the demand
    // subscription; the runtime-generation invalidation below runs only when
    // the AppearanceRuntimeContext itself changes.
    final demandSource = ref.watch(appearanceReconciliationDemandProvider);
    _subscribeToDemandSource(demandSource);
    final context = ref.watch(appearanceRuntimeContextProvider);
    if (context == _lastRuntimeContext) {
      // Only the demand source changed: preserve every read/mutation flag,
      // token, and published value for the current runtime generation.
      return _lastBuildValue ?? const AsyncLoading();
    }
    _lastRuntimeContext = context;
    // Any context change invalidates older completions and operation flags.
    _readToken++;
    _mutationToken++;
    _readInFlight = false;
    _mutationInFlight = false;
    _pendingReconciliationDemand = false;
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
    final AsyncValue<AppearanceSettingsState> result = retained == null
        ? const AsyncLoading()
        : AsyncData(retained);
    _lastBuildValue = result;
    scheduleMicrotask(() => unawaited(_adoptRuntimeContext(context)));
    return result;
  }

  /// Issues a focused authoritative read after a failure or uncertainty.
  ///
  /// Read-only recovery: this never calls [SettingsApi.updateAppearanceSettings].
  Future<void> retryAuthoritativeRead() async {
    final runtimeId = _activeRuntimeInstanceId;
    if (runtimeId == null || _readInFlight || _mutationInFlight) return;
    await _startFocusedRead(runtimeId);
  }

  Future<void> _startFocusedRead(RuntimeInstanceId runtimeId) async {
    if (state.hasError) {
      _setState(const AsyncLoading());
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
    _setState(AsyncData(refreshing));
    await _readAuthoritative(runtimeId, token: _readToken);
  }

  /// Admitted Phase 000 appearance mutation intent.
  ///
  /// A mutation and its mandatory post-command read form one single-flight
  /// operation. A successful update never promotes the requested value; only
  /// the confirming read becomes authority. Ambiguous transport failures are
  /// never replayed.
  Future<void> selectThemeMode(ThemeMode value) async {
    final current = state.value;
    if (current is! AppearanceSettingsStateReady ||
        _mutationInFlight ||
        _readInFlight ||
        current.synchronization is! AppearanceSynchronizationSynchronized) {
      return;
    }
    if (current.confirmed.themeMode == value) return;
    final runtimeId = _activeRuntimeInstanceId;
    if (runtimeId == null) return;

    final requested = current.confirmed.copyWith(themeMode: value);
    _mutationInFlight = true;
    final mutationToken = ++_mutationToken;
    _publish(
      AppearanceSettingsState.ready(
        confirmed: current.confirmed,
        presented: requested,
        saveOperation: AppearanceSaveOperation.saving(requested: requested),
        synchronization: current.synchronization,
      ),
    );

    final api = ref.read(appearanceSettingsApiProvider);
    try {
      await api.updateAppearanceSettings(requested);
      if (mutationToken != _mutationToken ||
          runtimeId != _activeRuntimeInstanceId) {
        return;
      }
      await _reconcileAfterMutation(
        runtimeId: runtimeId,
        mutationToken: mutationToken,
        readFailureSaveOperation: null,
      );
    } on ApplicationFailure catch (failure) {
      if (mutationToken != _mutationToken ||
          runtimeId != _activeRuntimeInstanceId) {
        return;
      }
      _mutationInFlight = false;
      final lastKnown = state.value!;
      _publish(
        AppearanceSettingsState.ready(
          confirmed: lastKnown.confirmed,
          presented: lastKnown.confirmed,
          saveOperation: AppearanceSaveOperation.failed(failure: failure),
          synchronization: const AppearanceSynchronization.synchronized(),
        ),
      );
      if (_pendingReconciliationDemand) {
        unawaited(_reconcileFromDemand());
      }
    } on TransportFailure catch (failure) {
      if (mutationToken != _mutationToken ||
          runtimeId != _activeRuntimeInstanceId) {
        return;
      }
      final lastKnown = state.value!;
      _publish(
        AppearanceSettingsState.ready(
          confirmed: lastKnown.confirmed,
          presented: lastKnown.confirmed,
          saveOperation: AppearanceSaveOperation.outcomeUnknown(
            failure: failure,
          ),
          synchronization: const AppearanceSynchronization.refreshing(),
        ),
      );
      await _reconcileAfterMutation(
        runtimeId: runtimeId,
        mutationToken: mutationToken,
        readFailureSaveOperation: AppearanceSaveOperation.outcomeUnknown(
          failure: failure,
        ),
      );
    }
  }

  Future<void> _reconcileAfterMutation({
    required RuntimeInstanceId runtimeId,
    required int mutationToken,
    required AppearanceSaveOperation? readFailureSaveOperation,
  }) async {
    await _readAuthoritative(
      runtimeId,
      token: _readToken,
      onFailure: (readFailure, current) {
        return AppearanceSettingsState.ready(
          confirmed: current.confirmed,
          presented: current.confirmed,
          saveOperation:
              readFailureSaveOperation ??
              AppearanceSaveOperation.committedButUnreconciled(
                failure: readFailure,
              ),
          synchronization: AppearanceSynchronization.uncertain(
            failure: readFailure,
          ),
        );
      },
    );
    if (mutationToken == _mutationToken) {
      _mutationInFlight = false;
      if (_pendingReconciliationDemand) {
        // A demand that arrived after the post-command read began must still
        // cause one follow-up once the save is no longer in flight.
        unawaited(_reconcileFromDemand());
      }
    }
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
    AppearanceSettingsState Function(
      ClientFailure failure,
      AppearanceSettingsState current,
    )?
    onFailure,
  }) async {
    if (_readInFlight) return;
    _readInFlight = true;
    // A demand known before this read started is covered by this read.
    _pendingReconciliationDemand = false;
    final api = ref.read(appearanceSettingsApiProvider);
    try {
      final result = await api.getAppearanceSettings();
      if (token != _readToken || runtimeId != _activeRuntimeInstanceId) return;
      final followUpPending = _pendingReconciliationDemand;
      _publish(
        AppearanceSettingsState.ready(
          confirmed: result,
          presented: result,
          saveOperation: const AppearanceSaveOperation.idle(),
          // A demand that arrived after this read began keeps synchronization
          // refreshing: the required follow-up read is still outstanding and
          // only its successful completion may publish synchronized.
          synchronization: followUpPending
              ? const AppearanceSynchronization.refreshing()
              : const AppearanceSynchronization.synchronized(),
        ),
      );
    } catch (error, stackTrace) {
      if (token != _readToken || runtimeId != _activeRuntimeInstanceId) return;
      final failure = _asClientFailure(error);
      final current = _lastLoaded;
      if (current == null) {
        _setState(AsyncError(failure, stackTrace));
      } else {
        final updated = onFailure != null
            ? onFailure(failure, current)
            : AppearanceSettingsState.ready(
                confirmed: current.confirmed,
                presented: current.confirmed,
                saveOperation: current.saveOperation,
                synchronization: AppearanceSynchronization.uncertain(
                  failure: failure,
                ),
              );
        _publish(updated);
      }
    } finally {
      if (token == _readToken) {
        _readInFlight = false;
        if (_pendingReconciliationDemand &&
            _activeRuntimeInstanceId == runtimeId) {
          // Route the follow-up through the focused-read helper so the
          // transition is coherent (refreshing/loading) instead of reading
          // while the previous completion left state synchronized/uncertain.
          unawaited(_reconcileFromDemand());
        }
      }
    }
  }

  Future<void> _reconcileFromDemand() async {
    final runtimeId = _activeRuntimeInstanceId;
    if (runtimeId == null) return;
    if (_readInFlight || _mutationInFlight) {
      // The demand is retained and causes one follow-up after the current
      // operation settles; it is never dropped as a presumed self-notification.
      _pendingReconciliationDemand = true;
      return;
    }
    await _startFocusedRead(runtimeId);
  }

  void _subscribeToDemandSource(AppearanceReconciliationDemandSource source) {
    _demandToken++;
    final token = _demandToken;
    final subscription = source.stream.listen((demand) {
      if (token != _demandToken) return;
      switch (demand) {
        case AppearanceReconciliationDemandRefresh():
          unawaited(_reconcileFromDemand());
      }
    });
    final previous = _demandSubscription;
    _demandSubscription = subscription;
    previous?.cancel();
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

  void _publish(AppearanceSettingsState loaded) {
    _lastLoaded = loaded;
    _setState(AsyncData(loaded));
  }

  void _setState(AsyncValue<AppearanceSettingsState> next) {
    _lastBuildValue = next;
    state = next;
  }

  ClientFailure _asClientFailure(Object error) {
    if (error is ClientFailure) return error;
    return TransportFailure('Unexpected appearance failure', cause: error);
  }
}
