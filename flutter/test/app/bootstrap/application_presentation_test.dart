import 'dart:async';

import 'package:argus/app/bootstrap/application_presentation_gate.dart';
import 'package:argus/app/bootstrap/appearance_event_coordinator.dart';
import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/app/routing/app_router.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/settings/application/appearance_settings_controller.dart';
import 'package:argus/features/settings/application/appearance_settings_dependencies.dart';
import 'package:argus/features/settings/application/appearance_settings_state.dart';
import 'package:argus/features/library/application/library_state.dart';
import 'package:argus/features/library/library_composition.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../features/settings/appearance_settings_test_fakes.dart';
import '../../features/library/library_test_fakes.dart';
import '../../features/startup/startup_test_fakes.dart';
import '../../core/client/jobs_gateway_stub.dart';
import '../../core/client/sources_gateway_stub.dart';

void main() {
  Widget buildGate({
    required FakeClientBootstrap bootstrap,
    required FakeSettingsApi settingsApi,
    FakeLibraryOnboardingApi? onboarding,
    bool supportsLibrary = true,
    AppTerminator? terminator,
    required Widget child,
  }) {
    final onboardingApi =
        onboarding ?? FakeLibraryOnboardingApi(_completeOnboardingState());
    return ProviderScope(
      overrides: [
        argusClientProvider.overrideWithValue(
          _presentationClient(supportsLibrary: supportsLibrary),
        ),
        clientBootstrapProvider.overrideWithValue(bootstrap),
        runtimeApiProvider.overrideWithValue(FakeRuntimeApi()),
        diagnosticsApiProvider.overrideWithValue(FakeDiagnosticsApi()),
        runtimeEventsProvider.overrideWithValue(FakeEventsApi()),
        appearanceSettingsApiProvider.overrideWithValue(settingsApi),
        libraryOnboardingApiProvider.overrideWithValue(onboardingApi),
        libraryRuntimeContextProvider.overrideWith((ref) {
          final runtimeInstanceId = ref.watch(readyRuntimeInstanceIdProvider);
          return runtimeInstanceId == null
              ? const LibraryRuntimeContext.preReady()
              : LibraryRuntimeContext.ready(
                  runtimeInstanceId: runtimeInstanceId,
                );
        }),
        appearanceRuntimeContextProvider.overrideWith((ref) {
          final runtimeInstanceId = ref.watch(readyRuntimeInstanceIdProvider);
          return runtimeInstanceId == null
              ? const AppearanceRuntimeContext.preReady()
              : AppearanceRuntimeContext.ready(
                  runtimeInstanceId: runtimeInstanceId,
                );
        }),
        appearanceReconciliationDemandProvider.overrideWith(
          (ref) => ref.watch(appearanceEventCoordinatorProvider),
        ),
        if (terminator != null)
          appTerminatorProvider.overrideWithValue(terminator),
      ],
      child: MaterialApp(home: ApplicationPresentationGate(child: child)),
    );
  }

  Widget buildApp({
    required FakeClientBootstrap bootstrap,
    required FakeSettingsApi settingsApi,
    FakeLibraryOnboardingApi? onboarding,
    bool supportsLibrary = true,
    required GoRouter router,
    FakeEventsApi? eventsApi,
  }) {
    final onboardingApi =
        onboarding ?? FakeLibraryOnboardingApi(_completeOnboardingState());
    return ProviderScope(
      overrides: [
        argusClientProvider.overrideWithValue(
          _presentationClient(supportsLibrary: supportsLibrary),
        ),
        appRouterProvider.overrideWithValue(router),
        clientBootstrapProvider.overrideWithValue(bootstrap),
        runtimeApiProvider.overrideWithValue(FakeRuntimeApi()),
        diagnosticsApiProvider.overrideWithValue(FakeDiagnosticsApi()),
        runtimeEventsProvider.overrideWithValue(eventsApi ?? FakeEventsApi()),
        appearanceSettingsApiProvider.overrideWithValue(settingsApi),
        libraryOnboardingApiProvider.overrideWithValue(onboardingApi),
        libraryRuntimeContextProvider.overrideWith((ref) {
          final runtimeInstanceId = ref.watch(readyRuntimeInstanceIdProvider);
          return runtimeInstanceId == null
              ? const LibraryRuntimeContext.preReady()
              : LibraryRuntimeContext.ready(
                  runtimeInstanceId: runtimeInstanceId,
                );
        }),
        appearanceRuntimeContextProvider.overrideWith((ref) {
          final runtimeInstanceId = ref.watch(readyRuntimeInstanceIdProvider);
          return runtimeInstanceId == null
              ? const AppearanceRuntimeContext.preReady()
              : AppearanceRuntimeContext.ready(
                  runtimeInstanceId: runtimeInstanceId,
                );
        }),
        appearanceReconciliationDemandProvider.overrideWith(
          (ref) => ref.watch(appearanceEventCoordinatorProvider),
        ),
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
    await tester.pump();

    expect(find.text('Settings shell'), findsOneWidget);
    expect(find.text('Loading appearance settings…'), findsNothing);
  });

  testWidgets(
    'backend ready + appearance ready + onboarding read pending shows initialization',
    (tester) async {
      final bootstrap = FakeClientBootstrap();
      final settingsApi = FakeSettingsApi();
      final onboarding = FakeLibraryOnboardingApi(_incompleteOnboardingState())
        ..getStateCompleter = Completer<LibraryOnboardingState>();

      await tester.pumpWidget(
        buildGate(
          bootstrap: bootstrap,
          settingsApi: settingsApi,
          onboarding: onboarding,
          child: shell(),
        ),
      );
      await makeBackendReady(tester, bootstrap);
      settingsApi.readRequests.single.complete(
        const AppearanceSettings(themeMode: ThemeMode.light),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Settings shell'), findsNothing);
      expect(onboarding.getStateCalls, 1);
    },
  );

  testWidgets('onboarding read failure shows a bounded retry surface', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final settingsApi = FakeSettingsApi();
    final onboarding = FakeLibraryOnboardingApi(_incompleteOnboardingState())
      ..getStateFailure = const TransportFailure('onboarding unavailable');
    var terminations = 0;

    await tester.pumpWidget(
      buildGate(
        bootstrap: bootstrap,
        settingsApi: settingsApi,
        onboarding: onboarding,
        terminator: () => terminations++,
        child: shell(),
      ),
    );
    await makeBackendReady(tester, bootstrap);
    settingsApi.readRequests.single.complete(
      const AppearanceSettings(themeMode: ThemeMode.light),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Library setup unavailable'), findsOneWidget);
    expect(
      find.text('Argus could not read the saved Library setup state.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Exit'), findsOneWidget);
    expect(find.text('Settings shell'), findsNothing);

    onboarding.getStateFailure = null;
    onboarding.state = _completeOnboardingState();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(onboarding.getStateCalls, 2);
    expect(find.text('Settings shell'), findsOneWidget);
    expect(terminations, 0);
  });

  testWidgets('incomplete authoritative onboarding admits the child', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final settingsApi = FakeSettingsApi();
    final onboarding = FakeLibraryOnboardingApi(_incompleteOnboardingState());

    await tester.pumpWidget(
      buildGate(
        bootstrap: bootstrap,
        settingsApi: settingsApi,
        onboarding: onboarding,
        child: shell(),
      ),
    );
    await makeBackendReady(tester, bootstrap);
    settingsApi.readRequests.single.complete(
      const AppearanceSettings(themeMode: ThemeMode.light),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Settings shell'), findsOneWidget);
    expect(onboarding.getStateCalls, 1);
  });

  testWidgets('complete authoritative onboarding admits the normal shell', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final settingsApi = FakeSettingsApi();
    final onboarding = FakeLibraryOnboardingApi(_completeOnboardingState());

    await tester.pumpWidget(
      buildGate(
        bootstrap: bootstrap,
        settingsApi: settingsApi,
        onboarding: onboarding,
        child: shell(),
      ),
    );
    await makeBackendReady(tester, bootstrap);
    settingsApi.readRequests.single.complete(
      const AppearanceSettings(themeMode: ThemeMode.light),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Settings shell'), findsOneWidget);
    expect(onboarding.getStateCalls, 1);
  });

  testWidgets('unsupported Library capability does not query onboarding', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final settingsApi = FakeSettingsApi();
    final onboarding = FakeLibraryOnboardingApi(_incompleteOnboardingState())
      ..getStateCompleter = Completer<LibraryOnboardingState>();

    await tester.pumpWidget(
      buildGate(
        bootstrap: bootstrap,
        settingsApi: settingsApi,
        onboarding: onboarding,
        supportsLibrary: false,
        child: shell(),
      ),
    );
    await makeBackendReady(tester, bootstrap);
    settingsApi.readRequests.single.complete(
      const AppearanceSettings(themeMode: ThemeMode.light),
    );
    await tester.pump();

    expect(find.text('Settings shell'), findsOneWidget);
    expect(onboarding.getStateCalls, 0);
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
    await tester.pump();

    expect(find.text('Settings shell'), findsOneWidget);
    // The first visible normal-shell frame must already be effective Dark.
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode?.name,
      'dark',
    );
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
    await tester.pump();
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
    await tester.pump();
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

    expect(
      Theme.of(tester.element(find.text('Settings shell'))).brightness,
      Brightness.dark,
    );
    expect(settingsApi.readRequests.length, readsBefore);
    expect(settingsApi.updateRequests.length, updatesBefore);
  });

  testWidgets(
    'event-driven root theme changes only after the authoritative query '
    'returns the new value',
    (tester) async {
      final bootstrap = FakeClientBootstrap();
      final settingsApi = FakeSettingsApi();
      final eventsApi = FakeEventsApi();
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
          eventsApi: eventsApi,
        ),
      );
      await tester.pump();
      await makeBackendReady(tester, bootstrap);
      settingsApi.readRequests.single.complete(
        const AppearanceSettings(themeMode: ThemeMode.light),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Settings shell'), findsOneWidget);
      expect(
        Theme.of(tester.element(find.text('Settings shell'))).brightness,
        Brightness.light,
      );

      // A committed backend change arrives as a payload-free notification.
      eventsApi.emit(
        RuntimeEvent(
          runtimeInstanceId: testId('a'),
          sequence: BigInt.one,
          occurredAtMs: BigInt.zero,
          payload: const RuntimeEventPayload.appearanceSettingsChanged(),
        ),
      );
      await tester.pump();
      await tester.pump();

      // The event alone must not change the root theme.
      expect(settingsApi.readRequests, hasLength(2));
      expect(settingsApi.updateRequests, isEmpty);
      expect(
        Theme.of(tester.element(find.text('Settings shell'))).brightness,
        Brightness.light,
      );

      settingsApi.readRequests[1].complete(
        const AppearanceSettings(themeMode: ThemeMode.dark),
      );
      await tester.pump();
      await tester.pump();

      expect(
        Theme.of(tester.element(find.text('Settings shell'))).brightness,
        Brightness.dark,
      );
      expect(settingsApi.updateRequests, isEmpty);
    },
  );
}

LibraryOnboardingState _incompleteOnboardingState() =>
    const LibraryOnboardingState(
      progress: LibraryOnboardingProgress(
        acceptedPrivacyTermsVersion: null,
        acceptedPrivacyAtMs: null,
        metadataPreferencesConfirmed: false,
        providerSetupOutcome: LibraryProviderSetupOutcome.pending,
        completedAtMs: null,
      ),
      requiredPrivacyTermsVersion: 'terms',
      requiresPrivacyAcceptance: true,
      requiresRootSelection: true,
      credentialConfigured: false,
      complete: false,
    );

LibraryOnboardingState _completeOnboardingState() =>
    const LibraryOnboardingState(
      progress: LibraryOnboardingProgress(
        acceptedPrivacyTermsVersion: 'terms',
        acceptedPrivacyAtMs: 1,
        metadataPreferencesConfirmed: true,
        providerSetupOutcome: LibraryProviderSetupOutcome.skipped,
        completedAtMs: 1,
      ),
      requiredPrivacyTermsVersion: 'terms',
      requiresPrivacyAcceptance: false,
      requiresRootSelection: false,
      credentialConfigured: false,
      complete: true,
    );

ArgusClient _presentationClient({required bool supportsLibrary}) => ArgusClient(
  gateway: supportsLibrary
      ? _LibraryPresentationGateway()
      : _PresentationGateway(),
);

/// Minimal gateway used to make presentation tests explicit about capability
/// support without initializing the native bridge.
class _PresentationGateway
    with SourcesGatewayStub, JobsGatewayStub
    implements ArgusClientGateway {
  static const _runtime = RuntimeInstanceId('cccccccccccccccccccccccccccccccc');

  RuntimeState get _ready =>
      const RuntimeState.ready(runtimeInstanceId: _runtime);

  @override
  Future<RuntimeState> getRuntimeState() async => _ready;

  @override
  Future<RuntimeState> initialize() async => _ready;

  @override
  Future<RuntimeState> retryStartup(RuntimeInstanceId expected) async => _ready;

  @override
  Future<RuntimeState> resetAppearanceSettings(
    RuntimeInstanceId expected,
  ) async => _ready;

  @override
  Future<RuntimeState> exitFailedRuntime(RuntimeInstanceId expected) async =>
      _ready;

  @override
  Future<void> generalShutdown() async {}

  @override
  Future<void> closeEventConnection() async {}

  @override
  Future<AppearanceSettings> getAppearanceSettings() async =>
      const AppearanceSettings(themeMode: ThemeMode.system);

  @override
  Future<void> updateAppearanceSettings(AppearanceSettings settings) async {}

  @override
  Future<DiagnosticsExport> exportStartupDiagnostics(
    RuntimeInstanceId expected,
    String destination,
  ) => throw UnsupportedError('Presentation test diagnostics are not focused');

  @override
  Future<TechnicalDetails> startupTechnicalDetails(
    RuntimeInstanceId expected,
  ) => throw UnsupportedError('Presentation test diagnostics are not focused');

  @override
  Future<void> openStartupDataDirectory(RuntimeInstanceId expected) =>
      throw UnsupportedError('Presentation test diagnostics are not focused');

  @override
  Future<EventBindResult> subscribeEvents(RuntimeInstanceId generation) async =>
      const EventBindResult(stream: Stream.empty(), nativeAttached: true);
}

final class _LibraryPresentationGateway extends _PresentationGateway
    implements LibraryPhase003Gateway {
  @override
  Future<LibraryOnboardingState> getLibraryOnboardingState() =>
      throw UnsupportedError('Presentation test onboarding is injected');

  @override
  Future<LibraryOnboardingState> confirmLibraryMetadataPreferences(
    MetadataSettings settings,
  ) => throw UnsupportedError('Presentation test onboarding is injected');

  @override
  Future<LibraryOnboardingState> recordLibraryProviderSetup(
    LibraryProviderSetupDecision decision,
  ) => throw UnsupportedError('Presentation test onboarding is injected');

  @override
  Future<CompleteLibraryOnboardingAndRefreshResult>
  completeLibraryOnboardingAndRefresh() =>
      throw UnsupportedError('Presentation test onboarding is injected');

  @override
  Future<AddLibraryRootAndRefreshResult> addLibraryRootAndRefresh(
    LocalFilesystemRootSelection selection,
  ) => throw UnsupportedError('Presentation test onboarding is injected');

  @override
  Future<MetadataSettings> getMetadataSettings() =>
      throw UnsupportedError('Presentation test onboarding is injected');

  @override
  Future<MetadataProviderSettings> getMetadataProviderSettings() =>
      throw UnsupportedError('Presentation test onboarding is injected');

  @override
  Future<MetadataSettingsUpdateResult> updateMetadataSettings(
    MetadataSettings settings,
  ) => throw UnsupportedError('Presentation test onboarding is injected');

  @override
  Future<MetadataProviderSettingsUpdateResult> updateMetadataProviderSettings(
    MetadataProviderSettings settings,
  ) => throw UnsupportedError('Presentation test onboarding is injected');

  @override
  Future<OperationHandle> startGameRefresh({
    required List<GameId> gameIds,
    required RefreshMode mode,
  }) => throw UnsupportedError('Presentation test onboarding is injected');

  @override
  Future<OperationHandle> refreshLibrary() =>
      throw UnsupportedError('Presentation test onboarding is injected');
}
