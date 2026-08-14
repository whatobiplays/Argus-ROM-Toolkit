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
    final container = ProviderContainer(
      overrides: [
        clientBootstrapProvider.overrideWithValue(FakeClientBootstrap()),
        runtimeApiProvider.overrideWithValue(FakeRuntimeApi()),
        diagnosticsApiProvider.overrideWithValue(FakeDiagnosticsApi()),
        runtimeEventsProvider.overrideWithValue(FakeEventsApi()),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(appReadinessProvider), AppReadiness.preReady);
    container.read(startupControllerProvider.notifier);
    expect(container.read(appReadinessProvider), AppReadiness.preReady);
  });
}
