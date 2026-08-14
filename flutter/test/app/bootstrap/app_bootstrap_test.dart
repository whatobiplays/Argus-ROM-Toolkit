import 'package:argus/app/bootstrap/app_bootstrap.dart';
import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/app/routing/app_router.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/settings/application/appearance_settings_dependencies.dart';
import 'package:argus/features/settings/application/appearance_settings_state.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../features/settings/appearance_settings_test_fakes.dart';
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
    final settingsApi = FakeSettingsApi();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clientBootstrapProvider.overrideWithValue(bootstrap),
          runtimeApiProvider.overrideWithValue(FakeRuntimeApi()),
          diagnosticsApiProvider.overrideWithValue(FakeDiagnosticsApi()),
          runtimeEventsProvider.overrideWithValue(FakeEventsApi()),
          appearanceSettingsApiProvider.overrideWithValue(settingsApi),
          appearanceRuntimeContextProvider.overrideWith((ref) {
            final runtimeInstanceId = ref.watch(readyRuntimeInstanceIdProvider);
            return runtimeInstanceId == null
                ? const AppearanceRuntimeContext.preReady()
                : AppearanceRuntimeContext.ready(
                    runtimeInstanceId: runtimeInstanceId,
                  );
          }),
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
    await tester.pump();

    // Backend Ready alone must not reveal the normal shell.
    expect(find.bySemanticsLabel('Settings'), findsNothing);
    expect(find.text('Loading appearance settings…'), findsOneWidget);

    settingsApi.readRequests.single.complete(
      const AppearanceSettings(themeMode: ThemeMode.light),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
  });

  testWidgets('ArgusApp accepts a test router through the provider seam', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final settingsApi = FakeSettingsApi();
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
          appearanceSettingsApiProvider.overrideWithValue(settingsApi),
          appearanceRuntimeContextProvider.overrideWith((ref) {
            final runtimeInstanceId = ref.watch(readyRuntimeInstanceIdProvider);
            return runtimeInstanceId == null
                ? const AppearanceRuntimeContext.preReady()
                : AppearanceRuntimeContext.ready(
                    runtimeInstanceId: runtimeInstanceId,
                  );
          }),
        ],
        child: const ArgusApp(),
      ),
    );
    bootstrap.completers.single.complete(
      RuntimeState.ready(runtimeInstanceId: testId('a')),
    );
    await tester.pump();

    // The router location is not disturbed by the appearance gate.
    expect(find.text('Test router page'), findsNothing);

    settingsApi.readRequests.single.complete(
      const AppearanceSettings(themeMode: ThemeMode.light),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test router page'), findsOneWidget);
    expect(testRouter.routerDelegate.currentConfiguration.uri.path, '/fixture');
  });
}
