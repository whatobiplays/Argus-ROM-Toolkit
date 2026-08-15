import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'sources_gateway_stub.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'initialize waits until the native event connection is attached',
    () async {
      final gateway = _AttachControlledGateway();
      final client = ArgusClient(gateway: gateway);
      var initializeCompleted = false;

      final initialize = client.initialize().then((state) {
        initializeCompleted = true;
        return state;
      });

      await pumpEventQueue();
      expect(gateway.subscribeCalls, 1);
      expect(gateway.nativeAttached, isFalse);
      expect(initializeCompleted, isFalse);

      gateway.attach.complete();
      final state = await initialize;

      expect(state, isA<RuntimeStateReady>());
      expect(gateway.nativeAttached, isTrue);
      expect(initializeCompleted, isTrue);

      await client.dispose();
    },
  );
}

final class _AttachControlledGateway
    with SourcesGatewayStub
    implements ArgusClientGateway {
  final RuntimeInstanceId id = RuntimeInstanceId('a' * 32);
  final Completer<void> attach = Completer<void>();
  final StreamController<RuntimeEvent> _events =
      StreamController<RuntimeEvent>.broadcast();
  int subscribeCalls = 0;
  bool nativeAttached = false;

  RuntimeState get _ready => RuntimeState.ready(runtimeInstanceId: id);

  @override
  Future<RuntimeState> initialize() async => _ready;

  @override
  Future<RuntimeState> getRuntimeState() async => _ready;

  @override
  Future<RuntimeState> retryStartup(RuntimeInstanceId expected) async => _ready;

  @override
  Future<RuntimeState> resetAppearanceSettings(
    RuntimeInstanceId expected,
  ) async => _ready;

  @override
  Future<RuntimeState> exitFailedRuntime(RuntimeInstanceId expected) async =>
      RuntimeState.stopped(runtimeInstanceId: expected);

  @override
  Future<void> generalShutdown() async {}

  @override
  Future<void> closeEventConnection() async {
    if (!_events.isClosed) await _events.close();
  }

  @override
  Future<AppearanceSettings> getAppearanceSettings() async =>
      const AppearanceSettings(themeMode: ThemeMode.system);

  @override
  Future<void> updateAppearanceSettings(AppearanceSettings settings) async {}

  @override
  Future<DiagnosticsExport> exportStartupDiagnostics(
    RuntimeInstanceId expected,
    String destination,
  ) async => const DiagnosticsExport(
    outcome: DiagnosticsExportOutcome.created,
    destinationClassification: 'test',
  );

  @override
  Future<TechnicalDetails> startupTechnicalDetails(
    RuntimeInstanceId expected,
  ) async => const TechnicalDetails(text: 'details');

  @override
  Future<void> openStartupDataDirectory(RuntimeInstanceId expected) async {}

  @override
  Future<EventBindResult> subscribeEvents(RuntimeInstanceId generation) async {
    subscribeCalls++;
    await attach.future;
    nativeAttached = true;
    return EventBindResult(stream: _events.stream, nativeAttached: true);
  }
}
