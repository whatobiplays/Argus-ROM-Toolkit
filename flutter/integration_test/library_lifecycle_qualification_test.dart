import 'dart:io';

import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/app_bootstrap.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/core/bridge/bridge.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Native desktop qualification for the app-lifetime Library reconciliation
/// path. The test uses the production bootstrap and native Rust bridge, while
/// the data directory is supplied by the host runner so the app sandbox and
/// teardown remain explicit.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final dataDirectory = Platform.environment['ARGUS_LIBRARY_DESKTOP_DATA_DIR'];
  if (dataDirectory == null ||
      dataDirectory.isEmpty ||
      !dataDirectory.startsWith('/')) {
    throw StateError(
      'ARGUS_LIBRARY_DESKTOP_DATA_DIR must be an absolute directory path',
    );
  }

  testWidgets('desktop Library lifecycle reconciliation stays single-runtime', (
    tester,
  ) async {
    ArgusClient? client;
    try {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ArgusBootstrap(
          clientGatewayFactory: () =>
              FrbArgusClientGateway(dataDirectoryOverride: dataDirectory),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ArgusApp)),
        listen: false,
      );
      client = container.read(argusClientProvider);
      final runtime = await _waitForRuntimeReady(tester, client!);
      final demands = <LibraryReconciliationDemand>[];
      final subscription = container
          .read(libraryReconciliationDemandProvider)
          .stream
          .listen(demands.add);
      addTearDown(subscription.cancel);

      final clientBefore = container.read(argusClientProvider);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      expect(
        demands.whereType<LibraryReconciliationDemandListChanged>(),
        isNotEmpty,
      );
      expect(
        identical(container.read(argusClientProvider), clientBefore),
        isTrue,
      );
      expect(await _readRuntimeInstanceId(client), runtime);
    } finally {
      final value = client;
      if (value != null) {
        try {
          await value.runtime.generalShutdown();
        } finally {
          await value.dispose();
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

Future<RuntimeInstanceId> _waitForRuntimeReady(
  WidgetTester tester,
  ArgusClient client,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  RuntimeState? lastState;
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      lastState = await client.runtime.getRuntimeState();
      if (lastState case RuntimeStateReady(:final runtimeInstanceId)) {
        return runtimeInstanceId;
      }
      if (lastState case RuntimeStateStartupFailed(:final failure)) {
        fail('desktop runtime startup failed: $failure');
      }
    } catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail(
    'desktop runtime did not become ready: state=$lastState error=$lastError',
  );
}

Future<RuntimeInstanceId> _readRuntimeInstanceId(ArgusClient client) async {
  final state = await client.runtime.getRuntimeState();
  return switch (state) {
    RuntimeStateReady(:final runtimeInstanceId) => runtimeInstanceId,
    _ => fail('desktop runtime left Ready during lifecycle qualification'),
  };
}
