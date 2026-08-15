import 'dart:async';

import 'package:argus/app/bootstrap/app_bootstrap.dart';
import 'package:argus/app/bootstrap/appearance_event_coordinator.dart';
import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/app/routing/app_router.dart';
import 'package:argus/core/client/client.dart';
import '../../core/client/sources_gateway_stub.dart';
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

  testWidgets('gateway factory seam preserves the app-owned composition', (
    tester,
  ) async {
    final pendingGateway = _PendingGateway();
    ArgusClientGateway gatewayFactory() => pendingGateway;

    await tester.pumpWidget(
      ArgusBootstrap(clientGatewayFactory: gatewayFactory),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ArgusApp)),
      listen: false,
    );

    expect(find.byType(ProviderScope), findsOneWidget);
    expect(
      container.read(argusClientGatewayFactoryProvider),
      same(gatewayFactory),
    );
    expect(
      identical(
        container.read(appearanceSettingsApiProvider),
        container.read(argusClientProvider).settings,
      ),
      isTrue,
    );
    expect(
      container.read(appearanceRuntimeContextProvider),
      const AppearanceRuntimeContext.preReady(),
    );
    expect(
      identical(
        container.read(appearanceReconciliationDemandProvider),
        container.read(appearanceEventCoordinatorProvider),
      ),
      isTrue,
    );
    // The startup attempt reaches the supplied gateway and stays pending, so
    // the pre-ready appearance runtime context is deterministic rather than
    // timing-dependent on a Ready completion.
    expect(pendingGateway.initializeCalls, 1);
    expect(pendingGateway.initialization.isCompleted, isFalse);
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

final class _PendingGateway
    with SourcesGatewayStub
    implements ArgusClientGateway {
  final Completer<RuntimeState> initialization = Completer<RuntimeState>();
  int initializeCalls = 0;

  @override
  Future<RuntimeState> initialize() {
    initializeCalls++;
    return initialization.future;
  }

  @override
  Future<RuntimeState> getRuntimeState() =>
      Future<RuntimeState>.error(UnimplementedError());

  @override
  Future<RuntimeState> retryStartup(RuntimeInstanceId expected) =>
      Future<RuntimeState>.error(UnimplementedError());

  @override
  Future<RuntimeState> resetAppearanceSettings(RuntimeInstanceId expected) =>
      Future<RuntimeState>.error(UnimplementedError());

  @override
  Future<RuntimeState> exitFailedRuntime(RuntimeInstanceId expected) =>
      Future<RuntimeState>.error(UnimplementedError());

  @override
  Future<void> generalShutdown() => Future<void>.error(UnimplementedError());

  @override
  Future<void> closeEventConnection() =>
      Future<void>.error(UnimplementedError());

  @override
  Future<AppearanceSettings> getAppearanceSettings() =>
      Future<AppearanceSettings>.error(UnimplementedError());

  @override
  Future<void> updateAppearanceSettings(AppearanceSettings settings) =>
      Future<void>.error(UnimplementedError());

  @override
  Future<DiagnosticsExport> exportStartupDiagnostics(
    RuntimeInstanceId expected,
    String destination,
  ) => Future<DiagnosticsExport>.error(UnimplementedError());

  @override
  Future<TechnicalDetails> startupTechnicalDetails(
    RuntimeInstanceId expected,
  ) => Future<TechnicalDetails>.error(UnimplementedError());

  @override
  Future<void> openStartupDataDirectory(RuntimeInstanceId expected) =>
      Future<void>.error(UnimplementedError());

  @override
  Future<EventBindResult> subscribeEvents(RuntimeInstanceId generation) =>
      Future<EventBindResult>.error(UnimplementedError());
}
