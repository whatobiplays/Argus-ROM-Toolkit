import 'package:argus/app/bootstrap/app_bootstrap.dart';
import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/app/routing/app_router.dart';
import 'package:argus/core/client/client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../features/startup/startup_test_fakes.dart';

void main() {
  testWidgets('ArgusBootstrap owns exactly one root ProviderScope', (
    tester,
  ) async {
    await tester.pumpWidget(const ArgusBootstrap());

    expect(find.byType(ProviderScope), findsOneWidget);
    await tester.pumpAndSettle();

    // Without a usable backend the default composition must stay pre-shell.
    expect(find.bySemanticsLabel('Settings'), findsNothing);
  });

  testWidgets('root composition blocks until authoritative backend Ready', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clientBootstrapProvider.overrideWithValue(bootstrap),
          runtimeApiProvider.overrideWithValue(FakeRuntimeApi()),
          diagnosticsApiProvider.overrideWithValue(FakeDiagnosticsApi()),
          runtimeEventsProvider.overrideWithValue(FakeEventsApi()),
        ],
        child: const ArgusApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Starting Argus…'), findsOneWidget);
    expect(find.bySemanticsLabel('Settings'), findsNothing);

    bootstrap.completers.single.complete(
      RuntimeState.ready(runtimeInstanceId: testId('a')),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
  });

  testWidgets('ArgusApp accepts a test router through the provider seam', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final testRouter = GoRouter(
      initialLocation: '/fixture',
      routes: <RouteBase>[
        GoRoute(
          path: '/fixture',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Test router page'))),
        ),
      ],
    );
    addTearDown(testRouter.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(testRouter),
          clientBootstrapProvider.overrideWithValue(bootstrap),
          runtimeApiProvider.overrideWithValue(FakeRuntimeApi()),
          diagnosticsApiProvider.overrideWithValue(FakeDiagnosticsApi()),
          runtimeEventsProvider.overrideWithValue(FakeEventsApi()),
        ],
        child: const ArgusApp(),
      ),
    );
    bootstrap.completers.single.complete(
      RuntimeState.ready(runtimeInstanceId: testId('a')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test router page'), findsOneWidget);
  });
}
