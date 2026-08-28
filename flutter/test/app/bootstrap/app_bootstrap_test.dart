import 'dart:async';

import 'package:argus/app/bootstrap/app_bootstrap.dart';
import 'package:argus/app/bootstrap/appearance_event_coordinator.dart';
import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/app/bootstrap/foreground_execution_coordinator.dart';
import 'package:argus/app/platform/native/desktop_platform_host_api.dart';
import 'package:argus/app/platform/platform_host.dart';
import 'package:argus/app/routing/app_router.dart';
import 'package:argus/core/bridge/src/frb_argus_client_gateway.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/library.dart';
import 'package:argus/features/jobs/jobs.dart';
import 'package:argus/features/sources/sources.dart';
import '../../core/client/jobs_gateway_stub.dart';
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
  final androidSnapshot = PlatformHostSnapshot(
    allFilesAccessRequired: true,
    allFilesAccessGranted: false,
    notificationAuthorization: NotificationAuthorization.promptRequired,
    standardApplicationDataDirectory:
        '/data/user/0/com.argusromtoolkit.argus/files/argus',
  );

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

  testWidgets('library folder picker seam overrides the picker inside the '
      'owned scope', (tester) async {
    const selection = LocalFilesystemRootSelection('/test-owned/folder');
    Future<SelectedLibraryFolder?> seam(BuildContext _, WidgetRef _) async =>
        const SelectedLibraryFolder(
          selection: selection,
          displayName: 'folder',
          safeLocationPresentation: '/test-owned/folder',
        );

    await tester.pumpWidget(ArgusBootstrap(libraryFolderPicker: seam));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ArgusApp)),
      listen: false,
    );

    // The seam is applied through the existing owned ProviderScope, so the
    // bootstrap still owns exactly one scope and no second override bag.
    expect(find.byType(ProviderScope), findsOneWidget);
    expect(container.read(libraryFolderPickerProvider), same(seam));
  });

  testWidgets(
    'Android readiness gate blocks backend initialization until Ready',
    (tester) async {
      final platformApi = _ReadinessPlatformHostApi(androidSnapshot);
      final pendingGateway = _PendingGateway();

      await tester.pumpWidget(
        ArgusBootstrap(
          platformHostComposition: PlatformHostComposition(
            api: platformApi,
            requiresReadinessGate: true,
          ),
          clientGatewayFactory: () => pendingGateway,
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ArgusApp)),
        listen: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(pendingGateway.initializeCalls, 0);
      expect(container.read(platformHostApiProvider), same(platformApi));

      platformApi.snapshot = PlatformHostSnapshot(
        allFilesAccessRequired: true,
        allFilesAccessGranted: true,
        notificationAuthorization: NotificationAuthorization.notRequired,
        standardApplicationDataDirectory:
            '/data/user/0/com.argusromtoolkit.argus/files/argus',
      );
      await container
          .read(platformReadinessControllerProvider.notifier)
          .refresh();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 400));

      expect(pendingGateway.initializeCalls, 1);
      expect(
        container.read(standardApplicationDataDirectoryProvider),
        isNull,
        reason:
            'a supplied clientGatewayFactory is authoritative and '
            'bypasses the production standard-data seam',
      );
      expect(
        container.read(startupPresentationCapabilitiesProvider),
        const StartupPresentationCapabilities(
          diagnosticsExport: true,
          diagnosticsSharing: true,
          openDataDirectory: false,
        ),
      );
    },
  );

  testWidgets(
    'Android production seam passes standard data to the gateway factory',
    (tester) async {
      final platformApi = _ReadinessPlatformHostApi(
        PlatformHostSnapshot(
          allFilesAccessRequired: true,
          allFilesAccessGranted: true,
          notificationAuthorization: NotificationAuthorization.notRequired,
          standardApplicationDataDirectory:
              '/data/user/0/com.argusromtoolkit.argus/files/argus',
        ),
      );
      await tester.pumpWidget(
        ArgusBootstrap(
          platformHostComposition: PlatformHostComposition(
            api: platformApi,
            requiresReadinessGate: true,
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ArgusApp)),
        listen: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        container.read(standardApplicationDataDirectoryProvider),
        '/data/user/0/com.argusromtoolkit.argus/files/argus',
      );
      expect(
        container.read(argusClientGatewayFactoryProvider)(),
        isA<FrbArgusClientGateway>(),
      );
    },
  );

  testWidgets('Android composition enables existing Sources workflows', (
    tester,
  ) async {
    final platformApi = _ReadinessPlatformHostApi(androidSnapshot);
    await tester.pumpWidget(
      ArgusBootstrap(
        platformHostComposition: PlatformHostComposition(
          api: platformApi,
          requiresReadinessGate: true,
        ),
        clientGatewayFactory: () => _PendingGateway(),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ArgusApp)),
      listen: false,
    );

    final capabilities = container.read(
      sourcesPresentationCapabilitiesProvider,
    );
    expect(capabilities.localFilesystemBrowser, isTrue);
    expect(capabilities.singleRootScanExecution, isTrue);
    expect(capabilities.scanAllExecution, isTrue);
    expect(capabilities.activeRootCancelAndRemove, isTrue);
    expect(
      container.read(startupPresentationCapabilitiesProvider),
      const StartupPresentationCapabilities(
        diagnosticsExport: true,
        diagnosticsSharing: true,
        openDataDirectory: false,
      ),
    );
  });

  testWidgets('Android composition decorates Sources and Jobs admissions', (
    tester,
  ) async {
    final host = _ForegroundExecutionHostStub();
    await tester.pumpWidget(
      ArgusBootstrap(
        platformHostComposition: PlatformHostComposition(
          api: _ReadinessPlatformHostApi(androidSnapshot),
          requiresReadinessGate: true,
          foregroundExecutionHostApi: host,
        ),
        clientGatewayFactory: () => _PendingGateway(),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ArgusApp)),
      listen: false,
    );

    expect(container.read(foregroundExecutionHostApiProvider), same(host));
    expect(
      container.read(sourcesApiProvider),
      isA<ForegroundHostedSourcesApi>(),
    );
    final jobsApi = container.read(jobsApiProvider);
    expect(jobsApi, isA<ForegroundHostedJobsApi>());
    expect(container.read(sourcesJobsApiProvider), same(jobsApi));
  });

  testWidgets(
    'Android storage transitions refresh Sources once without replaying Jobs',
    (tester) async {
      final platformApi = _ReadinessPlatformHostApi(
        PlatformHostSnapshot(
          allFilesAccessRequired: true,
          allFilesAccessGranted: true,
          notificationAuthorization: NotificationAuthorization.notRequired,
          standardApplicationDataDirectory:
              '/data/user/0/com.argusromtoolkit.argus/files/argus',
        ),
      );
      final volumes = _MountedVolumesStub([
        _volume('/storage/ABCD', '/mnt/first'),
      ]);
      await tester.pumpWidget(
        ArgusBootstrap(
          platformHostComposition: PlatformHostComposition(
            api: platformApi,
            requiresReadinessGate: true,
            localFilesystemApi: volumes,
          ),
          clientGatewayFactory: () => _PendingGateway(),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ArgusApp)),
        listen: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      final sourceDemands = <SourcesReconciliationDemand>[];
      final sourceSubscription = container
          .read(sourcesReconciliationDemandProvider)
          .stream
          .listen(sourceDemands.add);
      final jobDemands = <JobsReconciliationDemand>[];
      final jobSubscription = container
          .read(jobsReconciliationDemandProvider)
          .stream
          .listen(jobDemands.add);
      addTearDown(sourceSubscription.cancel);
      addTearDown(jobSubscription.cancel);

      volumes.volumes = [_volume('/storage/ABCD', '/mnt/remounted')];
      await container
          .read(platformReadinessControllerProvider.notifier)
          .refresh();
      await tester.pump();

      expect(sourceDemands, hasLength(1));
      expect(
        sourceDemands.single,
        isA<SourcesReconciliationDemandRootsChanged>(),
      );
      expect(jobDemands, isEmpty);

      await container
          .read(platformReadinessControllerProvider.notifier)
          .refresh();
      await tester.pump();

      expect(sourceDemands, hasLength(1));
      expect(jobDemands, isEmpty);
    },
  );

  test('desktop Sources capabilities retain every existing workflow', () {
    const capabilities = SourcesPresentationCapabilities();

    expect(capabilities.singleRootScanExecution, isTrue);
    expect(capabilities.scanAllExecution, isTrue);
    expect(capabilities.activeRootCancelAndRemove, isTrue);
    expect(capabilities.localFilesystemBrowser, isFalse);
  });

  testWidgets('desktop composition requires no readiness gate', (tester) async {
    await tester.pumpWidget(const ArgusBootstrap());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ArgusApp)),
      listen: false,
    );

    expect(
      container.read(platformHostApiProvider),
      isA<DesktopPlatformHostApi>(),
    );
    expect(container.read(standardApplicationDataDirectoryProvider), isNull);
  });

  testWidgets('resume fans one reconciliation demand through feature seams', (
    tester,
  ) async {
    final pendingGateway = _PendingGateway();
    await tester.pumpWidget(
      ArgusBootstrap(clientGatewayFactory: () => pendingGateway),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ArgusApp)),
      listen: false,
    );
    final libraryDemands = <LibraryReconciliationDemand>[];
    final librarySubscription = container
        .read(libraryReconciliationDemandProvider)
        .stream
        .listen(libraryDemands.add);
    final jobDemands = <JobsReconciliationDemand>[];
    final jobSubscription = container
        .read(jobsReconciliationDemandProvider)
        .stream
        .listen(jobDemands.add);
    final sourceDemands = <SourcesReconciliationDemand>[];
    final sourceSubscription = container
        .read(sourcesReconciliationDemandProvider)
        .stream
        .listen(sourceDemands.add);
    addTearDown(librarySubscription.cancel);
    addTearDown(jobSubscription.cancel);
    addTearDown(sourceSubscription.cancel);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(libraryDemands, hasLength(1));
    expect(
      libraryDemands.single,
      isA<LibraryReconciliationDemandListChanged>(),
    );
    expect(jobDemands, hasLength(1));
    expect(jobDemands.single, isA<JobsReconciliationDemandListChanged>());
    expect(sourceDemands, hasLength(1));
    expect(
      sourceDemands.single,
      isA<SourcesReconciliationDemandLifecycleChanged>(),
    );
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

    expect(find.bySemanticsLabel('Library'), findsOneWidget);
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
    with SourcesGatewayStub, JobsGatewayStub
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

final class _ReadinessPlatformHostApi implements PlatformHostApi {
  _ReadinessPlatformHostApi(this.snapshot);

  PlatformHostSnapshot snapshot;

  @override
  Future<void> openAllFilesAccessSettings() async {}

  @override
  Future<PlatformHostSnapshot> readSnapshot() async => snapshot;

  @override
  Future<NotificationAuthorization> requestNotificationPermission() async =>
      NotificationAuthorization.promptRequired;
}

final class _ForegroundExecutionHostStub implements ForegroundExecutionHostApi {
  @override
  Stream<ForegroundExecutionHostEvent> get events => const Stream.empty();

  @override
  Future<ForegroundExecutionLease> acquireLibraryScanLease() =>
      Future.value(const ForegroundExecutionLease('test-lease'));

  @override
  Future<void> releaseLease(ForegroundExecutionLease lease) async {}

  @override
  Future<void> updateProjection(
    ForegroundExecutionProjection projection,
  ) async {}
}

final class _MountedVolumesStub implements LocalFilesystemPlatformApi {
  _MountedVolumesStub(this.volumes);

  List<PlatformMountedVolume> volumes;

  @override
  Future<List<PlatformMountedVolume>> readMountedVolumes() async => volumes;
}

PlatformMountedVolume _volume(String id, String path) {
  return PlatformMountedVolume(
    providerVolumeId: id,
    transientMountPath: path,
    safeDisplayName: 'Removable volume',
    isPrimary: false,
    isRemovable: true,
  );
}
