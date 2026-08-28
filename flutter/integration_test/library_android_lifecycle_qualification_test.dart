import 'dart:async';
import 'dart:io';

import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/app_bootstrap.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/app/platform/native/android_qualification_api.dart';
import 'package:argus/app/platform/platform_host.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'phase_002_android_test_support.dart';

/// Exercises the Android Library lifecycle and native execution-host seams.
///
/// The shell runner owns the real background/foreground transition. Native
/// debug controls are limited to deterministic evidence of admission rejection,
/// platform timeout, and unexpected host destruction; durable Jobs state stays
/// behind the existing typed client APIs.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const evidencePath = String.fromEnvironment(
    'ARGUS_LIBRARY_ANDROID_EVIDENCE_PATH',
  );
  const continuePath = String.fromEnvironment(
    'ARGUS_LIBRARY_ANDROID_CONTINUE_PATH',
  );
  _requireAbsolutePath(evidencePath, 'ARGUS_LIBRARY_ANDROID_EVIDENCE_PATH');
  _requireAbsolutePath(continuePath, 'ARGUS_LIBRARY_ANDROID_CONTINUE_PATH');

  testWidgets('Android Library lifecycle remains single-runtime', (
    tester,
  ) async {
    ArgusClient? client;
    StreamSubscription<LibraryReconciliationDemand>? demandSubscription;
    try {
      await tester.pumpWidget(const ArgusBootstrap());
      await waitForPhase002PlatformReady(tester);
      client = await completePhase002LibraryOnboarding(tester);
      await _pumpUntil(
        tester,
        phase002ApplicationShellFinder(),
        message: 'Android application shell did not become ready',
      );

      final app = find.byType(ArgusApp);
      final container = ProviderScope.containerOf(
        tester.element(app),
        listen: false,
      );
      final rootClient = container.read(argusClientProvider);
      expect(identical(rootClient, client), isTrue);
      final runtimeBefore = await _readReadyRuntime(rootClient);
      final android = const AndroidQualificationApi();
      final activityBefore = await android.readActivityInstanceId();
      final demands = <LibraryReconciliationDemand>[];
      demandSubscription = container
          .read(libraryReconciliationDemandProvider)
          .stream
          .listen(demands.add);

      await _writeEvidence(
        evidencePath,
        'activity-before=$activityBefore\n'
        'runtime-before=$runtimeBefore\n',
      );
      await _writeMarker('$continuePath.ready');
      await _waitForMarker('$continuePath.background.done', tester);

      final activityAfter = await android.readActivityInstanceId();
      final runtimeAfter = await _readReadyRuntime(rootClient);
      expect(activityAfter, isNotEmpty);
      expect(runtimeAfter, runtimeBefore);
      await _waitForOneLibraryDemand(tester, demands);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        demands.whereType<LibraryReconciliationDemandListChanged>(),
        isNotEmpty,
      );

      final host = container.read(foregroundExecutionHostApiProvider);
      expect(host, isNotNull);
      final executionHost = host!;

      await android.rejectNextExecutionHostStart();
      await expectLater(
        executionHost.acquireLibraryScanLease(),
        throwsA(
          isA<TransportFailure>().having(
            (failure) => failure.kind,
            'kind',
            TransportFailureKind.communicationFailed,
          ),
        ),
      );

      final timeoutLease = await executionHost.acquireLibraryScanLease();
      expect(await android.triggerExecutionHostTimeout(), isTrue);
      await executionHost.releaseLease(timeoutLease);
      // The qualification control requests the real Android service stop;
      // Android dispatches onDestroy asynchronously after the callback.
      await tester.pump(const Duration(seconds: 2));

      final lossLease = await executionHost.acquireLibraryScanLease();
      expect(await android.triggerExecutionHostLoss(), isTrue);
      await tester.pump(const Duration(seconds: 2));
      await executionHost.releaseLease(lossLease);

      await _writeEvidence(
        evidencePath,
        'activity-after=$activityAfter\n'
        'activity-recreated=${activityAfter != activityBefore}\n'
        'runtime-after=$runtimeAfter\n'
        'reconciliation-demands=${demands.length}\n'
        'start-rejection=passed\n'
        'timeout=passed\n'
        'host-loss=passed\n',
      );
    } finally {
      await demandSubscription?.cancel();
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

void _requireAbsolutePath(String path, String name) {
  if (path.isEmpty || !path.startsWith('/')) {
    throw StateError('$name must be an absolute path');
  }
}

Future<RuntimeInstanceId> _readReadyRuntime(ArgusClient client) async {
  final state = await client.runtime.getRuntimeState();
  return switch (state) {
    RuntimeStateReady(:final runtimeInstanceId) => runtimeInstanceId,
    _ => fail('Android runtime left Ready during lifecycle qualification'),
  };
}

Future<void> _waitForOneLibraryDemand(
  WidgetTester tester,
  List<LibraryReconciliationDemand> demands,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    if (demands
        .whereType<LibraryReconciliationDemandListChanged>()
        .isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Android lifecycle did not publish a Library reconciliation demand');
}

Future<void> _waitForMarker(String path, WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    if (await File(path).exists()) return;
    await tester.pump(const Duration(milliseconds: 200));
  }
  fail('Timed out waiting for Android runner marker: $path');
}

Future<void> _writeMarker(String path) async {
  await File(path).writeAsString('ready\n', flush: true);
}

Future<void> _writeEvidence(String path, String contents) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(contents, mode: FileMode.append, flush: true);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  required String message,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 200));
  }
  fail(message);
}
