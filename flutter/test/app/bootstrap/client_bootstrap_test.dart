import 'dart:async';

import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/core/client/client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('host replacement retires the old client before publishing', () async {
    final gatewayA = _FakeGateway();
    final gatewayB = _FakeGateway();
    final factoryCalls = <ArgusClientGateway>[];
    final container = ProviderContainer(
      overrides: [
        argusClientGatewayFactoryProvider.overrideWithValue(() {
          final gateway = factoryCalls.isEmpty ? gatewayA : gatewayB;
          factoryCalls.add(gateway);
          return gateway;
        }),
      ],
    );
    addTearDown(container.dispose);

    final initial = container.read(argusClientProvider);
    expect(identical(initial, container.read(argusClientHostProvider)), isTrue);

    var initialClosed = false;
    initial.events.events.listen(null, onDone: () => initialClosed = true);

    final host = container.read(argusClientHostProvider.notifier);
    final replacementFuture = host.replace();

    // While disposal is in flight the old client remains the published root.
    expect(identical(container.read(argusClientProvider), initial), isTrue);

    final replacement = await replacementFuture;
    await pumpEventQueue();

    expect(initialClosed, isTrue);
    expect(identical(container.read(argusClientProvider), replacement), isTrue);
    expect(identical(replacement, host.current), isTrue);
    expect(factoryCalls, hasLength(2));
  });

  test(
    'bootstrap seam replaces the root client for every later attempt',
    () async {
      final gateways = <_FakeGateway>[_FakeGateway(), _FakeGateway()];
      var gatewayIndex = 0;
      final container = ProviderContainer(
        overrides: [
          argusClientGatewayFactoryProvider.overrideWithValue(
            () => gateways[gatewayIndex++],
          ),
        ],
      );
      addTearDown(container.dispose);

      final bootstrap = container.read(clientBootstrapProvider);
      final first = await bootstrap.initialize();
      final firstClient = container.read(argusClientProvider);
      expect(first, isA<RuntimeStateReady>());
      expect(gateways[0].initializeCalls, 1);

      var firstClosed = false;
      firstClient.events.events.listen(null, onDone: () => firstClosed = true);

      final second = await bootstrap.initialize();
      final secondClient = container.read(argusClientProvider);
      await pumpEventQueue();

      expect(second, isA<RuntimeStateReady>());
      expect(gateways[1].initializeCalls, 1);
      expect(identical(secondClient, firstClient), isFalse);
      expect(firstClosed, isTrue);
    },
  );

  test('container teardown disposes the current replacement client', () async {
    final gateways = <_FakeGateway>[_FakeGateway(), _FakeGateway()];
    var gatewayIndex = 0;
    final container = ProviderContainer(
      overrides: [
        argusClientGatewayFactoryProvider.overrideWithValue(
          () => gateways[gatewayIndex++],
        ),
      ],
    );
    addTearDown(container.dispose);

    final initial = container.read(argusClientProvider);
    var initialClosed = false;
    initial.events.events.listen(null, onDone: () => initialClosed = true);

    final host = container.read(argusClientHostProvider.notifier);
    final replacement = await host.replace();
    await pumpEventQueue();
    expect(initialClosed, isTrue);

    var replacementClosed = false;
    replacement.events.events.listen(
      null,
      onDone: () => replacementClosed = true,
    );

    container.dispose();
    await pumpEventQueue();

    expect(replacementClosed, isTrue);
  });

  test(
    'replacement is not published when retirement fails and failure latches',
    () async {
      final failingGateway = _FailingRetireGateway();
      final gateways = <ArgusClientGateway>[];
      final container = ProviderContainer(
        overrides: [
          argusClientGatewayFactoryProvider.overrideWithValue(() {
            final gateway = gateways.isEmpty ? failingGateway : _FakeGateway();
            gateways.add(gateway);
            return gateway;
          }),
        ],
      );
      addTearDown(container.dispose);

      final initial = container.read(argusClientProvider);
      await initial.initialize();
      final host = container.read(argusClientHostProvider.notifier);

      await expectLater(host.replace(), throwsA(isA<TransportFailure>()));
      expect(identical(container.read(argusClientProvider), initial), isTrue);
      expect(gateways, hasLength(2));

      await expectLater(host.replace(), throwsA(isA<TransportFailure>()));
      expect(gateways, hasLength(2));
      expect(identical(container.read(argusClientProvider), initial), isTrue);
    },
  );
}

final class _FakeGateway implements ArgusClientGateway {
  final StreamController<RuntimeEvent> _events =
      StreamController<RuntimeEvent>.broadcast();
  int initializeCalls = 0;
  RuntimeState state = RuntimeState.ready(
    runtimeInstanceId: RuntimeInstanceId('a' * 32),
  );

  @override
  Future<RuntimeState> initialize() {
    initializeCalls++;
    return Future<RuntimeState>.value(state);
  }

  @override
  Future<RuntimeState> getRuntimeState() => Future<RuntimeState>.value(state);

  @override
  Future<RuntimeState> retryStartup(RuntimeInstanceId expected) =>
      Future<RuntimeState>.value(state);

  @override
  Future<RuntimeState> resetAppearanceSettings(RuntimeInstanceId expected) =>
      Future<RuntimeState>.value(state);

  @override
  Future<RuntimeState> exitFailedRuntime(RuntimeInstanceId expected) =>
      Future<RuntimeState>.value(state);

  @override
  Future<void> generalShutdown() => Future<void>.value();

  @override
  Future<void> closeEventConnection() => Future<void>.value();

  @override
  Future<AppearanceSettings> getAppearanceSettings() =>
      Future<AppearanceSettings>.value(
        const AppearanceSettings(themeMode: ThemeMode.system),
      );

  @override
  Future<void> updateAppearanceSettings(AppearanceSettings settings) =>
      Future<void>.value();

  @override
  Future<DiagnosticsExport> exportStartupDiagnostics(
    RuntimeInstanceId expected,
    String destination,
  ) => Future<DiagnosticsExport>.value(
    const DiagnosticsExport(
      outcome: DiagnosticsExportOutcome.created,
      destinationClassification: 'test',
    ),
  );

  @override
  Future<TechnicalDetails> startupTechnicalDetails(
    RuntimeInstanceId expected,
  ) => Future<TechnicalDetails>.value(const TechnicalDetails(text: 'details'));

  @override
  Future<void> openStartupDataDirectory(RuntimeInstanceId expected) =>
      Future<void>.value();

  @override
  Future<EventBindResult> subscribeEvents(RuntimeInstanceId generation) async =>
      EventBindResult(stream: _events.stream, nativeAttached: true);
}

final class _FailingRetireGateway extends _FakeGateway {
  @override
  Future<void> closeEventConnection() async {
    throw StateError('close failed');
  }
}
