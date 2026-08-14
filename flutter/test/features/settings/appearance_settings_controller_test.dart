import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:argus/features/settings/application/appearance_settings_controller.dart';
import 'package:argus/features/settings/application/appearance_settings_dependencies.dart';
import 'package:argus/features/settings/application/appearance_settings_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'appearance_settings_test_fakes.dart';

void main() {
  late FakeSettingsApi api;
  late ProviderContainer container;

  setUp(() {
    api = FakeSettingsApi();
    container = ProviderContainer(
      overrides: [
        appearanceSettingsApiProvider.overrideWithValue(api),
        appearanceRuntimeContextProvider.overrideWith(
          (ref) => ref.watch(appearanceRuntimeContextHostProvider),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  AppearanceRuntimeContextHost runtimeHost() =>
      container.read(appearanceRuntimeContextHostProvider.notifier);

  /// Drains microtasks without elapsed-time sleeps.
  Future<void> settle() async {
    for (var i = 0; i < 100; i++) {
      await Future<void>.value();
    }
  }

  Future<AsyncValue<AppearanceSettingsState>> waitFor(
    bool Function(AsyncValue<AppearanceSettingsState> value) predicate,
  ) async {
    final current = container.read(appearanceSettingsControllerProvider);
    if (predicate(current)) return current;
    final completer = Completer<AsyncValue<AppearanceSettingsState>>();
    final subscription = container.listen<AsyncValue<AppearanceSettingsState>>(
      appearanceSettingsControllerProvider,
      (previous, next) {
        if (predicate(next) && !completer.isCompleted) completer.complete(next);
      },
    );
    addTearDown(subscription.close);
    return completer.future;
  }

  AppearanceSettingsState stateOf(AsyncValue<AppearanceSettingsState> value) =>
      value.value!;

  group('initial authoritative loading', () {
    test('preReady publishes no read and stays loading', () async {
      expect(
        container.read(appearanceSettingsControllerProvider),
        isA<AsyncLoading<AppearanceSettingsState>>(),
      );

      await settle();

      expect(api.readRequests, isEmpty);
      expect(
        container.read(appearanceSettingsControllerProvider),
        isA<AsyncLoading<AppearanceSettingsState>>(),
      );
    });

    test(
      'a ready runtime starts exactly one read and adopts its result',
      () async {
        runtimeHost().setContext(
          AppearanceRuntimeContext.ready(
            runtimeInstanceId: appearanceTestId('a'),
          ),
        );

        final loading = container.read(appearanceSettingsControllerProvider);
        expect(loading, isA<AsyncLoading<AppearanceSettingsState>>());
        await settle();
        expect(api.readRequests, hasLength(1));

        api.readRequests.single.complete(
          const AppearanceSettings(themeMode: ThemeMode.system),
        );
        final loaded = await waitFor((value) => value.hasValue);

        final state = stateOf(loaded);
        expect(state.confirmed.themeMode, ThemeMode.system);
        expect(state.presented.themeMode, ThemeMode.system);
        expect(state.saveOperation, const AppearanceSaveOperation.idle());
        expect(
          state.synchronization,
          const AppearanceSynchronization.synchronized(),
        );
        expect(api.readRequests, hasLength(1));
      },
    );

    for (final themeMode in ThemeMode.values) {
      test(
        'adopts authoritative $themeMode as confirmed and presented',
        () async {
          runtimeHost().setContext(
            AppearanceRuntimeContext.ready(
              runtimeInstanceId: appearanceTestId('a'),
            ),
          );
          container.read(appearanceSettingsControllerProvider);
          await settle();

          api.readRequests.single.complete(
            AppearanceSettings(themeMode: themeMode),
          );
          final loaded = await waitFor((value) => value.hasValue);
          final state = stateOf(loaded);
          expect(state.confirmed.themeMode, themeMode);
          expect(state.presented.themeMode, themeMode);
        },
      );
    }

    test(
      'initial ApplicationFailure becomes AsyncError without fabricating System',
      () async {
        runtimeHost().setContext(
          AppearanceRuntimeContext.ready(
            runtimeInstanceId: appearanceTestId('a'),
          ),
        );
        container.read(appearanceSettingsControllerProvider);
        await settle();
        final failure = ApplicationFailure(
          ClientApplicationError(
            code: const ErrorCode('ARGUS.V1.APPEARANCE.READ_FAILED'),
            category: ErrorCategory.persistence,
            severity: ApplicationSeverity.error,
            recoverability: Recoverability.userAction,
            retryPolicy: RetryPolicy.userInitiated,
            messageKey: const MessageKey('appearance.read_failed'),
            traceId: TraceId('b' * 32),
            safeContext: const <SafeContextEntry>[],
          ),
        );

        api.readRequests.single.completeError(failure);
        final errored = await waitFor((value) => value.hasError);

        expect(errored.error, same(failure));
        expect(errored, isA<AsyncError<AppearanceSettingsState>>());
      },
    );

    test(
      'initial TransportFailure becomes AsyncError without fabricating System',
      () async {
        runtimeHost().setContext(
          AppearanceRuntimeContext.ready(
            runtimeInstanceId: appearanceTestId('a'),
          ),
        );
        container.read(appearanceSettingsControllerProvider);
        await settle();
        const failure = TransportFailure(
          'runtime unreachable',
          kind: TransportFailureKind.communicationFailed,
        );

        api.readRequests.single.completeError(failure);
        final errored = await waitFor((value) => value.hasError);

        expect(errored.error, same(failure));
        expect(errored, isA<AsyncError<AppearanceSettingsState>>());
      },
    );
  });

  group('runtime-generation safety', () {
    test(
      'Runtime A completions cannot publish after Runtime B becomes current',
      () async {
        runtimeHost().setContext(
          AppearanceRuntimeContext.ready(
            runtimeInstanceId: appearanceTestId('a'),
          ),
        );
        container.read(appearanceSettingsControllerProvider);
        await settle();
        expect(api.readRequests, hasLength(1));

        runtimeHost().setContext(
          AppearanceRuntimeContext.ready(
            runtimeInstanceId: appearanceTestId('b'),
          ),
        );
        container.read(appearanceSettingsControllerProvider);
        await settle();
        expect(api.readRequests, hasLength(2));

        api.readRequests[0].complete(
          const AppearanceSettings(themeMode: ThemeMode.dark),
        );
        await settle();
        expect(
          container.read(appearanceSettingsControllerProvider),
          isA<AsyncLoading<AppearanceSettingsState>>(),
        );

        api.readRequests[1].complete(
          const AppearanceSettings(themeMode: ThemeMode.light),
        );
        final loaded = await waitFor((value) => value.hasValue);
        expect(stateOf(loaded).confirmed.themeMode, ThemeMode.light);
      },
    );

    test(
      'replacement after a loaded snapshot retains last-known and refreshes',
      () async {
        runtimeHost().setContext(
          AppearanceRuntimeContext.ready(
            runtimeInstanceId: appearanceTestId('a'),
          ),
        );
        container.read(appearanceSettingsControllerProvider);
        await settle();
        api.readRequests[0].complete(
          const AppearanceSettings(themeMode: ThemeMode.dark),
        );
        await waitFor((value) => value.hasValue);

        runtimeHost().setContext(
          AppearanceRuntimeContext.ready(
            runtimeInstanceId: appearanceTestId('b'),
          ),
        );
        container.read(appearanceSettingsControllerProvider);
        await settle();

        final refreshed = container.read(appearanceSettingsControllerProvider);
        final state = stateOf(refreshed);
        expect(state.confirmed.themeMode, ThemeMode.dark);
        expect(state.presented.themeMode, ThemeMode.dark);
        expect(state.saveOperation, const AppearanceSaveOperation.idle());
        expect(
          state.synchronization,
          isA<AppearanceSynchronizationRefreshing>(),
        );
        expect(api.readRequests, hasLength(2));

        api.readRequests[1].complete(
          const AppearanceSettings(themeMode: ThemeMode.light),
        );
        final loaded = await waitFor(
          (value) =>
              value.hasValue &&
              value.value!.synchronization
                  is AppearanceSynchronizationSynchronized,
        );
        expect(stateOf(loaded).confirmed.themeMode, ThemeMode.light);
      },
    );

    test(
      'replacement read failure retains last-known and marks uncertainty',
      () async {
        runtimeHost().setContext(
          AppearanceRuntimeContext.ready(
            runtimeInstanceId: appearanceTestId('a'),
          ),
        );
        container.read(appearanceSettingsControllerProvider);
        await settle();
        api.readRequests[0].complete(
          const AppearanceSettings(themeMode: ThemeMode.dark),
        );
        await waitFor((value) => value.hasValue);

        runtimeHost().setContext(
          AppearanceRuntimeContext.ready(
            runtimeInstanceId: appearanceTestId('b'),
          ),
        );
        container.read(appearanceSettingsControllerProvider);
        await settle();
        const failure = TransportFailure(
          'read failed on B',
          kind: TransportFailureKind.communicationFailed,
        );
        api.readRequests[1].completeError(failure);

        final loaded = await waitFor(
          (value) =>
              value.hasValue &&
              value.value!.synchronization
                  is AppearanceSynchronizationUncertain,
        );
        final state = stateOf(loaded);
        expect(state.confirmed.themeMode, ThemeMode.dark);
        expect(state.presented.themeMode, ThemeMode.dark);
        final uncertain =
            state.synchronization as AppearanceSynchronizationUncertain;
        expect(uncertain.failure, same(failure));
      },
    );
  });

  group('read-only retry', () {
    test('issues no request without a ready runtime', () async {
      final notifier = container.read(
        appearanceSettingsControllerProvider.notifier,
      );

      await notifier.retryAuthoritativeRead();
      await settle();

      expect(api.readRequests, isEmpty);
    });

    test('coalesces with an in-flight read', () async {
      runtimeHost().setContext(
        AppearanceRuntimeContext.ready(
          runtimeInstanceId: appearanceTestId('a'),
        ),
      );
      container.read(appearanceSettingsControllerProvider);
      await settle();
      final notifier = container.read(
        appearanceSettingsControllerProvider.notifier,
      );

      await notifier.retryAuthoritativeRead();

      expect(api.readRequests, hasLength(1));
    });

    test('maps outer error to loading and re-reads', () async {
      runtimeHost().setContext(
        AppearanceRuntimeContext.ready(
          runtimeInstanceId: appearanceTestId('a'),
        ),
      );
      container.read(appearanceSettingsControllerProvider);
      await settle();
      const failure = TransportFailure(
        'first read failed',
        kind: TransportFailureKind.communicationFailed,
      );
      api.readRequests[0].completeError(failure);
      await waitFor((value) => value.hasError);

      final notifier = container.read(
        appearanceSettingsControllerProvider.notifier,
      );
      final retryFuture = notifier.retryAuthoritativeRead();
      expect(
        container.read(appearanceSettingsControllerProvider),
        isA<AsyncLoading<AppearanceSettingsState>>(),
      );
      expect(api.readRequests, hasLength(2));

      api.readRequests[1].complete(
        const AppearanceSettings(themeMode: ThemeMode.light),
      );
      await retryFuture;
      final loaded = await waitFor((value) => value.hasValue);
      expect(stateOf(loaded).confirmed.themeMode, ThemeMode.light);
      expect(api.updateRequests, isEmpty);
    });

    test(
      'maps loaded uncertainty to refreshing and re-reads read-only',
      () async {
        runtimeHost().setContext(
          AppearanceRuntimeContext.ready(
            runtimeInstanceId: appearanceTestId('a'),
          ),
        );
        container.read(appearanceSettingsControllerProvider);
        await settle();
        api.readRequests[0].complete(
          const AppearanceSettings(themeMode: ThemeMode.dark),
        );
        await waitFor((value) => value.hasValue);

        runtimeHost().setContext(
          AppearanceRuntimeContext.ready(
            runtimeInstanceId: appearanceTestId('b'),
          ),
        );
        container.read(appearanceSettingsControllerProvider);
        await settle();
        const failure = TransportFailure(
          'B read failed',
          kind: TransportFailureKind.communicationFailed,
        );
        api.readRequests[1].completeError(failure);
        await waitFor(
          (value) =>
              value.hasValue &&
              value.value!.synchronization
                  is AppearanceSynchronizationUncertain,
        );

        final notifier = container.read(
          appearanceSettingsControllerProvider.notifier,
        );
        final retryFuture = notifier.retryAuthoritativeRead();
        final refreshing = container.read(appearanceSettingsControllerProvider);
        expect(
          stateOf(refreshing).synchronization,
          isA<AppearanceSynchronizationRefreshing>(),
        );
        expect(api.readRequests, hasLength(3));

        api.readRequests[2].complete(
          const AppearanceSettings(themeMode: ThemeMode.light),
        );
        await retryFuture;
        final loaded = await waitFor(
          (value) =>
              value.hasValue &&
              value.value!.synchronization
                  is AppearanceSynchronizationSynchronized,
        );
        expect(stateOf(loaded).confirmed.themeMode, ThemeMode.light);
        expect(api.updateRequests, isEmpty);
      },
    );
  });

  group('immediate single-flight mutation', () {
    Future<void> loadConfirmed(ThemeMode mode) async {
      runtimeHost().setContext(
        AppearanceRuntimeContext.ready(
          runtimeInstanceId: appearanceTestId('a'),
        ),
      );
      container.read(appearanceSettingsControllerProvider);
      await settle();
      api.readRequests[0].complete(AppearanceSettings(themeMode: mode));
      await waitFor((value) => value.hasValue);
    }

    test(
      'pending selection presents optimistically while authority is single-flight',
      () async {
        await loadConfirmed(ThemeMode.light);
        final notifier = container.read(
          appearanceSettingsControllerProvider.notifier,
        );

        final selection = notifier.selectThemeMode(ThemeMode.dark);

        final pending = container.read(appearanceSettingsControllerProvider);
        final state = stateOf(pending);
        expect(state.confirmed.themeMode, ThemeMode.light);
        expect(state.presented.themeMode, ThemeMode.dark);
        expect(
          state.saveOperation,
          const AppearanceSaveOperation.saving(
            requested: AppearanceSettings(themeMode: ThemeMode.dark),
          ),
        );
        expect(
          state.synchronization,
          const AppearanceSynchronization.synchronized(),
        );
        expect(api.updateRequests, hasLength(1));
        expect(api.updateRequests.single.settings.themeMode, ThemeMode.dark);

        // A second selection while the first is pending creates no new update.
        await notifier.selectThemeMode(ThemeMode.system);
        expect(api.updateRequests, hasLength(1));

        api.updateRequests.single.completer.complete();
        await settle();
        api.readRequests[1].complete(
          const AppearanceSettings(themeMode: ThemeMode.dark),
        );
        await selection;

        final loaded = await waitFor(
          (value) =>
              value.hasValue &&
              value.value!.saveOperation is AppearanceSaveOperationIdle,
        );
        expect(stateOf(loaded).confirmed.themeMode, ThemeMode.dark);
        expect(stateOf(loaded).presented.themeMode, ThemeMode.dark);
      },
    );

    test(
      'selecting the already-confirmed value while idle performs no write',
      () async {
        await loadConfirmed(ThemeMode.light);
        final notifier = container.read(
          appearanceSettingsControllerProvider.notifier,
        );

        await notifier.selectThemeMode(ThemeMode.light);

        expect(api.updateRequests, isEmpty);
      },
    );

    test(
      'update success reconciles through a mandatory read that wins',
      () async {
        await loadConfirmed(ThemeMode.light);
        final notifier = container.read(
          appearanceSettingsControllerProvider.notifier,
        );

        final selection = notifier.selectThemeMode(ThemeMode.dark);
        api.updateRequests.single.completer.complete();
        await settle();

        // Success alone must not promote the requested value.
        final beforeRead = container.read(appearanceSettingsControllerProvider);
        final state = stateOf(beforeRead);
        expect(state.confirmed.themeMode, ThemeMode.light);
        expect(state.presented.themeMode, ThemeMode.dark);
        expect(state.saveOperation, isA<AppearanceSaveOperationSaving>());
        expect(api.readRequests, hasLength(2));

        api.readRequests[1].complete(
          const AppearanceSettings(themeMode: ThemeMode.dark),
        );
        await selection;
        final loaded = await waitFor(
          (value) =>
              value.hasValue &&
              value.value!.synchronization
                  is AppearanceSynchronizationSynchronized,
        );
        expect(stateOf(loaded).confirmed.themeMode, ThemeMode.dark);
        expect(
          stateOf(loaded).saveOperation,
          const AppearanceSaveOperation.idle(),
        );
      },
    );

    test('a query result different from the submitted value wins', () async {
      await loadConfirmed(ThemeMode.light);
      final notifier = container.read(
        appearanceSettingsControllerProvider.notifier,
      );

      final selection = notifier.selectThemeMode(ThemeMode.dark);
      api.updateRequests.single.completer.complete();
      await settle();
      api.readRequests[1].complete(
        const AppearanceSettings(themeMode: ThemeMode.light),
      );
      await selection;

      final loaded = await waitFor((value) => value.hasValue);
      expect(stateOf(loaded).confirmed.themeMode, ThemeMode.light);
      expect(stateOf(loaded).presented.themeMode, ThemeMode.light);
    });

    test(
      'definite ApplicationFailure rolls presentation back and stays synchronized',
      () async {
        await loadConfirmed(ThemeMode.light);
        final notifier = container.read(
          appearanceSettingsControllerProvider.notifier,
        );
        final failure = ApplicationFailure(
          ClientApplicationError(
            code: const ErrorCode('ARGUS.V1.APPEARANCE.UPDATE_FAILED'),
            category: ErrorCategory.persistence,
            severity: ApplicationSeverity.error,
            recoverability: Recoverability.userAction,
            retryPolicy: RetryPolicy.userInitiated,
            messageKey: const MessageKey('appearance.update_failed'),
            traceId: TraceId('c' * 32),
            safeContext: const <SafeContextEntry>[],
          ),
        );

        final selection = notifier.selectThemeMode(ThemeMode.dark);
        api.updateRequests.single.completer.completeError(failure);
        await selection;

        final rolledBack = await waitFor(
          (value) =>
              value.hasValue &&
              value.value!.saveOperation is AppearanceSaveOperationFailed,
        );
        final state = stateOf(rolledBack);
        expect(state.confirmed.themeMode, ThemeMode.light);
        expect(state.presented.themeMode, ThemeMode.light);
        expect(
          state.saveOperation,
          isA<AppearanceSaveOperationFailed>().having(
            (operation) => operation.failure,
            'failure',
            same(failure),
          ),
        );
        expect(
          state.synchronization,
          const AppearanceSynchronization.synchronized(),
        );
        expect(api.readRequests, hasLength(1));

        // A later different selection remains admissible.
        final retrySelection = notifier.selectThemeMode(ThemeMode.dark);
        expect(api.updateRequests, hasLength(2));
        api.updateRequests[1].completer.completeError(failure);
        await retrySelection;
        await waitFor(
          (value) =>
              value.hasValue &&
              value.value!.saveOperation is AppearanceSaveOperationFailed,
        );
      },
    );

    test(
      'ambiguous TransportFailure never replays and reconciles by read',
      () async {
        await loadConfirmed(ThemeMode.light);
        final notifier = container.read(
          appearanceSettingsControllerProvider.notifier,
        );
        const failure = TransportFailure(
          'update outcome unknown',
          kind: TransportFailureKind.communicationFailed,
        );

        final selection = notifier.selectThemeMode(ThemeMode.dark);
        api.updateRequests.single.completer.completeError(failure);
        await settle();

        final awaiting = container.read(appearanceSettingsControllerProvider);
        final state = stateOf(awaiting);
        expect(state.confirmed.themeMode, ThemeMode.light);
        expect(state.presented.themeMode, ThemeMode.light);
        expect(
          state.saveOperation,
          isA<AppearanceSaveOperationOutcomeUnknown>().having(
            (operation) => operation.failure,
            'failure',
            same(failure),
          ),
        );
        expect(
          state.synchronization,
          isA<AppearanceSynchronizationRefreshing>(),
        );
        expect(api.readRequests, hasLength(2));

        api.readRequests[1].complete(
          const AppearanceSettings(themeMode: ThemeMode.dark),
        );
        await selection;
        final loaded = await waitFor(
          (value) =>
              value.hasValue &&
              value.value!.synchronization
                  is AppearanceSynchronizationSynchronized,
        );
        expect(stateOf(loaded).confirmed.themeMode, ThemeMode.dark);
        expect(
          stateOf(loaded).saveOperation,
          const AppearanceSaveOperation.idle(),
        );
        expect(api.updateRequests, hasLength(1));
      },
    );

    test(
      'ambiguous mutation plus failed read retains last-known and blocks writes',
      () async {
        await loadConfirmed(ThemeMode.light);
        final notifier = container.read(
          appearanceSettingsControllerProvider.notifier,
        );
        const updateFailure = TransportFailure(
          'update outcome unknown',
          kind: TransportFailureKind.communicationFailed,
        );
        const readFailure = TransportFailure(
          'reconciliation read failed',
          kind: TransportFailureKind.communicationFailed,
        );

        final selection = notifier.selectThemeMode(ThemeMode.dark);
        api.updateRequests.single.completer.completeError(updateFailure);
        await settle();
        api.readRequests[1].completeError(readFailure);
        await selection;

        final uncertain = await waitFor(
          (value) =>
              value.hasValue &&
              value.value!.synchronization
                  is AppearanceSynchronizationUncertain,
        );
        final state = stateOf(uncertain);
        expect(state.confirmed.themeMode, ThemeMode.light);
        expect(state.presented.themeMode, ThemeMode.light);
        final save =
            state.saveOperation as AppearanceSaveOperationOutcomeUnknown;
        expect(save.failure, same(updateFailure));
        final sync =
            state.synchronization as AppearanceSynchronizationUncertain;
        expect(sync.failure, same(readFailure));

        await notifier.selectThemeMode(ThemeMode.dark);
        expect(api.updateRequests, hasLength(1));

        final retryFuture = notifier.retryAuthoritativeRead();
        expect(api.readRequests, hasLength(3));
        api.readRequests[2].complete(
          const AppearanceSettings(themeMode: ThemeMode.light),
        );
        await retryFuture;
        final refreshed = await waitFor(
          (value) =>
              value.hasValue &&
              value.value!.synchronization
                  is AppearanceSynchronizationSynchronized,
        );
        expect(
          stateOf(refreshed).saveOperation,
          const AppearanceSaveOperation.idle(),
        );
      },
    );

    test(
      'update success plus failed read becomes committed-but-unreconciled',
      () async {
        await loadConfirmed(ThemeMode.light);
        final notifier = container.read(
          appearanceSettingsControllerProvider.notifier,
        );
        const readFailure = TransportFailure(
          'reconciliation read failed',
          kind: TransportFailureKind.communicationFailed,
        );

        final selection = notifier.selectThemeMode(ThemeMode.dark);
        api.updateRequests.single.completer.complete();
        await settle();
        api.readRequests[1].completeError(readFailure);
        await selection;

        final uncertain = await waitFor(
          (value) =>
              value.hasValue &&
              value.value!.saveOperation
                  is AppearanceSaveOperationCommittedButUnreconciled,
        );
        final state = stateOf(uncertain);
        expect(state.confirmed.themeMode, ThemeMode.light);
        expect(state.presented.themeMode, ThemeMode.light);
        final save =
            state.saveOperation
                as AppearanceSaveOperationCommittedButUnreconciled;
        expect(save.failure, same(readFailure));
        expect(
          state.synchronization,
          isA<AppearanceSynchronizationUncertain>(),
        );

        await notifier.selectThemeMode(ThemeMode.dark);
        expect(api.updateRequests, hasLength(1));

        final retryFuture = notifier.retryAuthoritativeRead();
        expect(api.readRequests, hasLength(3));
        api.readRequests[2].complete(
          const AppearanceSettings(themeMode: ThemeMode.dark),
        );
        await retryFuture;
        final refreshed = await waitFor(
          (value) =>
              value.hasValue &&
              value.value!.confirmed.themeMode == ThemeMode.dark &&
              value.value!.saveOperation is AppearanceSaveOperationIdle,
        );
        expect(
          stateOf(refreshed).synchronization,
          const AppearanceSynchronization.synchronized(),
        );
      },
    );

    test(
      'runtime replacement ignores all A-era mutation completions',
      () async {
        await loadConfirmed(ThemeMode.light);
        final notifier = container.read(
          appearanceSettingsControllerProvider.notifier,
        );

        final selection = notifier.selectThemeMode(ThemeMode.dark);
        expect(api.updateRequests, hasLength(1));

        runtimeHost().setContext(
          AppearanceRuntimeContext.ready(
            runtimeInstanceId: appearanceTestId('b'),
          ),
        );
        container.read(appearanceSettingsControllerProvider);
        await settle();
        expect(api.readRequests, hasLength(2));

        // A's update completion must be ignored entirely.
        api.updateRequests.single.completer.complete();
        await settle();
        expect(api.readRequests, hasLength(2));
        await selection;

        api.readRequests[1].complete(
          const AppearanceSettings(themeMode: ThemeMode.light),
        );
        final loaded = await waitFor(
          (value) =>
              value.hasValue &&
              value.value!.synchronization
                  is AppearanceSynchronizationSynchronized,
        );
        expect(stateOf(loaded).confirmed.themeMode, ThemeMode.light);
        expect(
          stateOf(loaded).saveOperation,
          const AppearanceSaveOperation.idle(),
        );

        final secondSelection = notifier.selectThemeMode(ThemeMode.dark);
        expect(api.updateRequests, hasLength(2));
        api.updateRequests[1].completer.complete();
        await settle();
        api.readRequests[2].complete(
          const AppearanceSettings(themeMode: ThemeMode.dark),
        );
        await secondSelection;
        final adopted = await waitFor(
          (value) =>
              value.hasValue &&
              value.value!.confirmed.themeMode == ThemeMode.dark,
        );
        expect(stateOf(adopted).presented.themeMode, ThemeMode.dark);
      },
    );
  });
}
