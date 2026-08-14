import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/app/routing/app_router.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'startup_test_fakes.dart';

void main() {
  Future<void> pumpGate(
    WidgetTester tester, {
    required FakeClientBootstrap bootstrap,
    FakeRuntimeApi? runtime,
    FakeDiagnosticsApi? diagnostics,
    FakeEventsApi? events,
    AppTerminator? terminator,
    Widget? routedChild,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clientBootstrapProvider.overrideWithValue(bootstrap),
          runtimeApiProvider.overrideWithValue(runtime ?? FakeRuntimeApi()),
          diagnosticsApiProvider.overrideWithValue(
            diagnostics ?? FakeDiagnosticsApi(),
          ),
          runtimeEventsProvider.overrideWithValue(events ?? FakeEventsApi()),
          if (terminator != null)
            appTerminatorProvider.overrideWithValue(terminator),
        ],
        child: MaterialApp(
          builder: (context, child) => StartupGate(child: child!),
          home: routedChild ?? const Scaffold(body: Text('ROUTED')),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('gate blocks on startup and exposes child only at Ready', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    await pumpGate(tester, bootstrap: bootstrap);

    expect(find.text('Starting Argus…'), findsOneWidget);
    expect(find.text('ROUTED'), findsNothing);

    bootstrap.completers.single.complete(
      RuntimeState.ready(runtimeInstanceId: testId('a')),
    );
    await tester.pumpAndSettle();

    expect(find.text('ROUTED'), findsOneWidget);
    expect(find.text('Starting Argus…'), findsNothing);
  });

  testWidgets('gate shows recovery surface for StartupFailed', (tester) async {
    final bootstrap = FakeClientBootstrap();
    await pumpGate(tester, bootstrap: bootstrap);

    bootstrap.completers.single.complete(failedRuntime(id: 'a'));
    await tester.pumpAndSettle();

    expect(find.text('Argus could not start'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('reset-appearance-settings-button')),
      findsOneWidget,
    );
    expect(find.text('ROUTED'), findsNothing);
  });

  testWidgets('gate shows bootstrap failure surface on transport failure', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    await pumpGate(tester, bootstrap: bootstrap);

    bootstrap.completers.single.completeError(
      const TransportFailure('native unavailable'),
      StackTrace.current,
    );
    await tester.pumpAndSettle();

    expect(find.text('Argus could not initialize'), findsOneWidget);
    expect(find.text('ROUTED'), findsNothing);
  });

  testWidgets('bootstrap Retry triggers a fresh attempt through the gate', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    await pumpGate(tester, bootstrap: bootstrap);

    bootstrap.completers.first.completeError(
      const TransportFailure('attempt A failed'),
      StackTrace.current,
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('retry-initialization-button')),
    );
    await tester.pump();
    expect(bootstrap.initializeCalls, 2);

    bootstrap.completers.last.complete(
      RuntimeState.ready(runtimeInstanceId: testId('b')),
    );
    await tester.pumpAndSettle();
    expect(find.text('ROUTED'), findsOneWidget);
  });

  testWidgets('gate shows runtime-unavailable surface and check action', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final runtime = FakeRuntimeApi()
      ..getRuntimeStateError = const TransportFailure('still unreachable');
    await pumpGate(tester, bootstrap: bootstrap, runtime: runtime);

    bootstrap.completers.single.complete(failedRuntime(id: 'a'));
    await tester.pumpAndSettle();

    final controller = ProviderScope.containerOf(
      tester.element(find.byType(StartupGate)),
    ).read(startupControllerProvider.notifier);
    final retry = controller.retryStartup();
    runtime.retryRequests.single.completer.completeError(
      const TransportFailure('ambiguous transport outcome'),
      StackTrace.current,
    );
    await retry;
    await tester.pumpAndSettle();

    expect(find.text('Connection to Argus was lost'), findsOneWidget);
    expect(find.text('ROUTED'), findsNothing);

    runtime.getRuntimeStateError = null;
    runtime.getRuntimeStateResult = RuntimeState.ready(
      runtimeInstanceId: testId('b'),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('check-runtime-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('ROUTED'), findsOneWidget);
  });

  testWidgets('stopped state terminates the application once', (tester) async {
    final bootstrap = FakeClientBootstrap();
    var terminated = 0;
    await pumpGate(
      tester,
      bootstrap: bootstrap,
      terminator: () => terminated++,
    );

    bootstrap.completers.single.complete(
      RuntimeState.stopped(runtimeInstanceId: testId('a')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Argus has stopped'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('stopped-close-button')),
      findsNothing,
    );
    expect(terminated, 1);

    await tester.pump();
    expect(terminated, 1);
  });

  testWidgets('intended /settings route survives startup failure and retry', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final runtime = FakeRuntimeApi();
    final container = ProviderContainer(
      overrides: [
        clientBootstrapProvider.overrideWithValue(bootstrap),
        runtimeApiProvider.overrideWithValue(runtime),
        diagnosticsApiProvider.overrideWithValue(FakeDiagnosticsApi()),
        runtimeEventsProvider.overrideWithValue(FakeEventsApi()),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const ArgusApp()),
    );
    await tester.pump();

    router.go('/settings');
    await tester.pump();
    expect(find.bySemanticsLabel('Settings'), findsNothing);
    expect(find.text('Starting Argus…'), findsOneWidget);

    bootstrap.completers.single.complete(failedRuntime(id: 'a'));
    await tester.pumpAndSettle();
    expect(find.text('Argus could not start'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/settings');

    final controller = container.read(startupControllerProvider.notifier);
    final retry = controller.retryStartup();
    runtime.retryRequests.single.completer.complete(
      RuntimeState.ready(runtimeInstanceId: testId('b')),
    );
    await retry;
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/settings');
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      isNot(contains('/startup')),
    );
  });
}
