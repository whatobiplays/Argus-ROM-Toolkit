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
}
