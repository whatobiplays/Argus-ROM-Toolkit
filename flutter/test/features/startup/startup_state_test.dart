import 'package:argus/core/client/client.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'startup_test_fakes.dart';

void main() {
  test('startup state variants carry only their valid fields', () {
    final ready = StartupState.ready(runtimeInstanceId: testId('a'));

    expect(ready, isA<StartupStateReady>());
    expect(startupRuntimeId(ready), testId('a'));
    final unavailable =
        StartupState.runtimeUnavailable(
              cause: const TransportFailure('x'),
              lastKnownRuntime: null,
              reconciliationOperation:
                  const ReconciliationOperationState.idle(),
            )
            as StartupStateRuntimeUnavailable;
    expect(unavailable.lastKnownRuntime, isNull);
  });

  test('appReadiness is ready only for authoritative Ready', () async {
    final bootstrap = FakeClientBootstrap();
    final container = ProviderContainer(
      overrides: [
        clientBootstrapProvider.overrideWithValue(bootstrap),
        runtimeApiProvider.overrideWithValue(FakeRuntimeApi()),
        diagnosticsApiProvider.overrideWithValue(FakeDiagnosticsApi()),
        runtimeEventsProvider.overrideWithValue(FakeEventsApi()),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(appReadinessProvider), AppReadiness.preReady);
    expect(container.read(readyRuntimeInstanceIdProvider), isNull);
    container.read(startupControllerProvider.notifier);
    expect(container.read(appReadinessProvider), AppReadiness.preReady);
    expect(container.read(readyRuntimeInstanceIdProvider), isNull);

    bootstrap.completers.single.complete(
      RuntimeState.ready(runtimeInstanceId: testId('a')),
    );
    for (var i = 0; i < 100; i++) {
      await Future<void>.value();
    }

    expect(container.read(appReadinessProvider), AppReadiness.ready);
    expect(container.read(readyRuntimeInstanceIdProvider), testId('a'));
  });

  test(
    'readyRuntimeInstanceId stays null while startup never becomes Ready',
    () async {
      final bootstrap = FakeClientBootstrap();
      final container = ProviderContainer(
        overrides: [
          clientBootstrapProvider.overrideWithValue(bootstrap),
          runtimeApiProvider.overrideWithValue(FakeRuntimeApi()),
          diagnosticsApiProvider.overrideWithValue(FakeDiagnosticsApi()),
          runtimeEventsProvider.overrideWithValue(FakeEventsApi()),
        ],
      );
      addTearDown(container.dispose);

      container.read(startupControllerProvider.notifier);
      bootstrap.completers.single.completeError(
        const TransportFailure('startup failed'),
      );
      for (var i = 0; i < 100; i++) {
        await Future<void>.value();
      }

      expect(container.read(appReadinessProvider), AppReadiness.preReady);
      expect(container.read(readyRuntimeInstanceIdProvider), isNull);
    },
  );
}
