import 'package:argus/app/bootstrap/application_presentation_gate.dart';
import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/app/routing/app_router.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/settings/application/appearance_settings_controller.dart';
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
  Widget buildGate({
    required FakeClientBootstrap bootstrap,
    required FakeSettingsApi settingsApi,
    AppTerminator? terminator,
    required Widget child,
  }) {
    return ProviderScope(
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
        if (terminator != null)
          appTerminatorProvider.overrideWithValue(terminator),
      ],
      child: MaterialApp(home: ApplicationPresentationGate(child: child)),
    );
  }

  Widget buildApp({
    required FakeClientBootstrap bootstrap,
    required FakeSettingsApi settingsApi,
    required GoRouter router,
  }) {
    return ProviderScope(
      overrides: [
        appRouterProvider.overrideWithValue(router),
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
    );
  }

  Widget shell() => const Scaffold(body: Center(child: Text('Settings shell')));

  Future<void> makeBackendReady(
    WidgetTester tester,
    FakeClientBootstrap bootstrap,
  ) async {
    bootstrap.completers.single.complete(
      RuntimeState.ready(runtimeInstanceId: testId('a')),
    );
    await tester.pump();
  }

  testWidgets('preReady renders no routed child and no appearance surface', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final settingsApi = FakeSettingsApi();

    await tester.pumpWidget(
      buildGate(bootstrap: bootstrap, settingsApi: settingsApi, child: shell()),
    );
    await tester.pump();

    expect(find.text('Settings shell'), findsNothing);
    expect(find.text('Loading appearance settings…'), findsNothing);
    expect(find.text('Appearance unavailable'), findsNothing);
  });

  testWidgets(
    'backend Ready with pending read shows initialization and no shell',
    (tester) async {
      final bootstrap = FakeClientBootstrap();
      final settingsApi = FakeSettingsApi();

      await tester.pumpWidget(
        buildGate(
          bootstrap: bootstrap,
          settingsApi: settingsApi,
          child: shell(),
        ),
      );
      await makeBackendReady(tester, bootstrap);

      expect(find.text('Loading appearance settings…'), findsOneWidget);
      expect(find.text('Settings shell'), findsNothing);
    },
  );

  testWidgets('initial read failure shows the typed failure surface', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final settingsApi = FakeSettingsApi();

    await tester.pumpWidget(
      buildGate(bootstrap: bootstrap, settingsApi: settingsApi, child: shell()),
    );
    await makeBackendReady(tester, bootstrap);

    settingsApi.readRequests.single.completeError(
      const TransportFailure(
        'runtime unreachable',
        kind: TransportFailureKind.communicationFailed,
      ),
    );
    await tester.pump();

    expect(find.text('Appearance unavailable'), findsOneWidget);
    expect(
      find.text(
        'Argus could not reach its runtime to load appearance settings.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Exit'), findsOneWidget);
    expect(find.text('Settings shell'), findsNothing);
  });

  testWidgets('failure Retry issues only a read and admits the shell', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final settingsApi = FakeSettingsApi();
    var terminations = 0;

    await tester.pumpWidget(
      buildGate(
        bootstrap: bootstrap,
        settingsApi: settingsApi,
        terminator: () => terminations++,
        child: shell(),
      ),
    );
    await makeBackendReady(tester, bootstrap);
    settingsApi.readRequests.single.completeError(
      const TransportFailure('initial failure'),
    );
    await tester.pump();

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(settingsApi.readRequests, hasLength(2));
    expect(settingsApi.updateRequests, isEmpty);
    settingsApi.readRequests[1].complete(
      const AppearanceSettings(themeMode: ThemeMode.light),
    );
    await tester.pump();

    expect(find.text('Settings shell'), findsOneWidget);
    expect(terminations, 0);
  });

  testWidgets('failure Exit invokes the composition termination seam', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final settingsApi = FakeSettingsApi();
    var terminations = 0;

    await tester.pumpWidget(
      buildGate(
        bootstrap: bootstrap,
        settingsApi: settingsApi,
        terminator: () => terminations++,
        child: shell(),
      ),
    );
    await makeBackendReady(tester, bootstrap);
    settingsApi.readRequests.single.completeError(
      const TransportFailure('initial failure'),
    );
    await tester.pump();

    await tester.tap(find.text('Exit'));
    await tester.pump();

    expect(terminations, 1);
    expect(settingsApi.updateRequests, isEmpty);
  });

  testWidgets('authoritative snapshot admits the routed shell', (tester) async {
    final bootstrap = FakeClientBootstrap();
    final settingsApi = FakeSettingsApi();

    await tester.pumpWidget(
      buildGate(bootstrap: bootstrap, settingsApi: settingsApi, child: shell()),
    );
    await makeBackendReady(tester, bootstrap);
    settingsApi.readRequests.single.complete(
      const AppearanceSettings(themeMode: ThemeMode.light),
    );
    await tester.pump();

    expect(find.text('Settings shell'), findsOneWidget);
    expect(find.text('Loading appearance settings…'), findsNothing);
  });

  testWidgets('first normal shell frame after authoritative Dark is dark', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final settingsApi = FakeSettingsApi();
    final testRouter = GoRouter(
      initialLocation: '/fixture',
      routes: <RouteBase>[
        GoRoute(path: '/fixture', builder: (context, state) => shell()),
      ],
    );
    addTearDown(testRouter.dispose);

    await tester.pumpWidget(
      buildApp(
        bootstrap: bootstrap,
        settingsApi: settingsApi,
        router: testRouter,
      ),
    );
    await tester.pump();
    expect(find.text('Settings shell'), findsNothing);

    await makeBackendReady(tester, bootstrap);
    expect(find.text('Settings shell'), findsNothing);

    settingsApi.readRequests.single.complete(
      const AppearanceSettings(themeMode: ThemeMode.dark),
    );
    await tester.pump();

    expect(find.text('Settings shell'), findsOneWidget);
    // The root theme authority is dark on the first shell frame; the default
    // theme animation settles the effective brightness immediately after.
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode?.name,
      'dark',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      Theme.of(tester.element(find.text('Settings shell'))).brightness,
      Brightness.dark,
    );
    expect(testRouter.routerDelegate.currentConfiguration.uri.path, '/fixture');
  });

  testWidgets('pending root authority keeps the root theme confirmed', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final settingsApi = FakeSettingsApi();
    final testRouter = GoRouter(
      initialLocation: '/fixture',
      routes: <RouteBase>[
        GoRoute(path: '/fixture', builder: (context, state) => shell()),
      ],
    );
    addTearDown(testRouter.dispose);

    await tester.pumpWidget(
      buildApp(
        bootstrap: bootstrap,
        settingsApi: settingsApi,
        router: testRouter,
      ),
    );
    await makeBackendReady(tester, bootstrap);
    settingsApi.readRequests.single.complete(
      const AppearanceSettings(themeMode: ThemeMode.light),
    );
    await tester.pump();
    expect(find.text('Settings shell'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('Settings shell'))).brightness,
      Brightness.light,
    );

    final container = ProviderScope.containerOf(
      tester.element(find.text('Settings shell')),
    );
    final selection = container
        .read(appearanceSettingsControllerProvider.notifier)
        .selectThemeMode(ThemeMode.dark);
    await tester.pump();

    final pending = container.read(appearanceSettingsControllerProvider);
    expect(pending.value!.presented.themeMode, ThemeMode.dark);
    expect(pending.value!.confirmed.themeMode, ThemeMode.light);
    expect(
      Theme.of(tester.element(find.text('Settings shell'))).brightness,
      Brightness.light,
    );

    settingsApi.updateRequests.single.completer.complete();
    await tester.pump();
    settingsApi.readRequests[1].complete(
      const AppearanceSettings(themeMode: ThemeMode.dark),
    );
    await selection;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      Theme.of(tester.element(find.text('Settings shell'))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('System follows platform brightness without settings traffic', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final settingsApi = FakeSettingsApi();
    final testRouter = GoRouter(
      initialLocation: '/fixture',
      routes: <RouteBase>[
        GoRoute(path: '/fixture', builder: (context, state) => shell()),
      ],
    );
    addTearDown(testRouter.dispose);

    await tester.pumpWidget(
      buildApp(
        bootstrap: bootstrap,
        settingsApi: settingsApi,
        router: testRouter,
      ),
    );
    await tester.pump();
    await makeBackendReady(tester, bootstrap);
    settingsApi.readRequests.single.complete(
      const AppearanceSettings(themeMode: ThemeMode.system),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Settings shell'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('Settings shell'))).brightness,
      Brightness.light,
    );

    final readsBefore = settingsApi.readRequests.length;
    final updatesBefore = settingsApi.updateRequests.length;
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      Theme.of(tester.element(find.text('Settings shell'))).brightness,
      Brightness.dark,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.text('Settings shell')),
    );
    expect(
      container
          .read(appearanceSettingsControllerProvider)
          .value!
          .confirmed
          .themeMode,
      ThemeMode.system,
    );
    expect(settingsApi.readRequests.length, readsBefore);
    expect(settingsApi.updateRequests.length, updatesBefore);
  });

  testWidgets('explicit Dark ignores platform brightness changes', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final settingsApi = FakeSettingsApi();
    final testRouter = GoRouter(
      initialLocation: '/fixture',
      routes: <RouteBase>[
        GoRoute(path: '/fixture', builder: (context, state) => shell()),
      ],
    );
    addTearDown(testRouter.dispose);

    await tester.pumpWidget(
      buildApp(
        bootstrap: bootstrap,
        settingsApi: settingsApi,
        router: testRouter,
      ),
    );
    await tester.pump();
    await makeBackendReady(tester, bootstrap);
    settingsApi.readRequests.single.complete(
      const AppearanceSettings(themeMode: ThemeMode.dark),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      Theme.of(tester.element(find.text('Settings shell'))).brightness,
      Brightness.dark,
    );

    final readsBefore = settingsApi.readRequests.length;
    final updatesBefore = settingsApi.updateRequests.length;
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      Theme.of(tester.element(find.text('Settings shell'))).brightness,
      Brightness.dark,
    );
    expect(settingsApi.readRequests.length, readsBefore);
    expect(settingsApi.updateRequests.length, updatesBefore);
  });
}
