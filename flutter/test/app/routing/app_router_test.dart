import 'dart:async';

import 'package:argus/app/bootstrap/application_presentation.dart';
import 'package:argus/app/routing/app_destination.dart';
import 'package:argus/app/routing/app_router.dart';
import 'package:argus/app/routing/app_routes.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/core/design_system/argus_theme.dart';
import 'package:argus/features/settings/application/appearance_settings_dependencies.dart';
import 'package:argus/features/settings/application/appearance_settings_state.dart';
import 'package:argus/features/library/library_composition.dart';
import 'package:argus/features/library/application/library_state.dart';
import 'package:argus/features/sources/sources_composition.dart';
import 'package:argus/features/sources/application/sources_state.dart';
import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/settings/appearance_settings_test_fakes.dart';
import '../../features/library/library_test_fakes.dart';
import '../../features/sources/sources_test_fakes.dart';

void main() {
  test('typed production routes and semantic mappings are canonical', () {
    expect(const LibraryRoute().location, '/library');
    expect(
      const LibraryPlatformRoute(platformId: 'nintendo_gb').location,
      '/library/platforms/nintendo_gb',
    );
    expect(
      const LibrarySourceRoute(sourceId: 'source-1').location,
      '/library/sources/source-1',
    );
    expect(
      const LibraryRootScopeRoute(
        libraryRootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ).location,
      '/library/library-roots/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    expect(const SettingsRoute().location, '/settings');
    expect(const SourcesRoute().location, '/sources');
    expect(destinationForUri(Uri.parse('/library')), AppDestination.library);
    expect(
      destinationForUri(Uri.parse('/games/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')),
      AppDestination.library,
    );
    expect(destinationForUri(Uri.parse('/settings')), AppDestination.settings);
    expect(destinationForUri(Uri.parse('/sources')), AppDestination.sources);
    expect(
      destinationForUri(
        Uri.parse('/sources/roots/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
      ),
      AppDestination.sources,
    );
    expect(
      destinationForUri(Uri.parse('/settings?source=test')),
      AppDestination.settings,
    );
    expect(destinationForUri(Uri.parse('/unknown')), isNull);
  });

  ({
    ProviderContainer container,
    FakeSettingsApi api,
    FakeSourcesApi sourcesApi,
    FakeLibraryReads libraryReads,
    FakeLibraryOnboardingApi onboarding,
  })
  createHost({
    FakeSourcesApi? sources,
    FakeLibraryReads? reads,
    FakeLibraryOnboardingApi? onboarding,
    ApplicationPresentationReadiness readiness =
        ApplicationPresentationReadiness.ready,
  }) {
    final api = FakeSettingsApi();
    final sourcesApi = sources ?? FakeSourcesApi();
    final libraryReads = reads ?? FakeLibraryReads();
    final onboardingApi =
        onboarding ??
        FakeLibraryOnboardingApi(completeLibraryOnboardingState());
    final container = ProviderContainer(
      overrides: [
        applicationPresentationReadinessProvider.overrideWithValue(readiness),
        appearanceSettingsApiProvider.overrideWithValue(api),
        appearanceRuntimeContextProvider.overrideWith(
          (ref) => ref.watch(appearanceRuntimeContextHostProvider),
        ),
        sourcesApiProvider.overrideWithValue(sourcesApi),
        librarySourcesApiProvider.overrideWithValue(sourcesApi),
        libraryApiProvider.overrideWithValue(libraryReads),
        libraryMetadataSettingsApiProvider.overrideWithValue(
          _RouterMetadataSettingsApi(),
        ),
        libraryMetadataProvidersApiProvider.overrideWithValue(
          _RouterMetadataProvidersApi(),
        ),
        libraryRefreshApiProvider.overrideWithValue(FakeLibraryRefreshApi()),
        libraryGamesApiProvider.overrideWithValue(FakeGamesApi()),
        libraryReconciliationDemandProvider.overrideWithValue(
          const LibraryReconciliationDemandSource(
            Stream<LibraryReconciliationDemand>.empty(),
          ),
        ),
        libraryOnboardingApiProvider.overrideWithValue(onboardingApi),
        libraryRuntimeContextProvider.overrideWithValue(
          const LibraryRuntimeContext.ready(
            runtimeInstanceId: RuntimeInstanceId(
              '1234567890abcdef1234567890abcdef',
            ),
          ),
        ),
        sourcesRuntimeContextProvider.overrideWith(
          (ref) => const SourcesRuntimeContext.ready(
            runtimeInstanceId: RuntimeInstanceId(
              '1234567890abcdef1234567890abcdef',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(appearanceRuntimeContextHostProvider.notifier)
        .setContext(
          AppearanceRuntimeContext.ready(
            runtimeInstanceId: appearanceTestId('a'),
          ),
        );
    return (
      container: container,
      api: api,
      sourcesApi: sourcesApi,
      libraryReads: libraryReads,
      onboarding: onboardingApi,
    );
  }

  Future<void> loadAppearance(WidgetTester tester, FakeSettingsApi api) async {
    await tester.pump();
    if (api.readRequests.isEmpty) return;
    api.readRequests.single.complete(
      const AppearanceSettings(themeMode: ThemeMode.light),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('root redirects to Library and renders the Library shell', (
    tester,
  ) async {
    final host = createHost();
    final router = host.container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: host.container,
        child: const _RouterHost(),
      ),
    );
    await loadAppearance(tester, host.api);

    expect(router.routeInformationProvider.value.uri.path, '/library');
    expect(find.bySemanticsLabel('Library'), findsOneWidget);
  });

  testWidgets('direct Settings navigation renders Settings', (tester) async {
    final host = createHost();
    final router = host.container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: host.container,
        child: const _RouterHost(),
      ),
    );
    router.go('/settings');
    await loadAppearance(tester, host.api);

    expect(router.routeInformationProvider.value.uri.path, '/settings');
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
  });

  testWidgets(
    'library-unavailable readiness redirects every Library destination to Settings',
    (tester) async {
      final host = createHost(
        readiness: ApplicationPresentationReadiness.libraryUnavailable,
      );
      final router = host.container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: host.container,
          child: const _RouterHost(),
        ),
      );
      await loadAppearance(tester, host.api);

      for (final path in <String>[
        '/library',
        '/library/platforms/nintendo_gb',
        '/games/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ]) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/settings');
      }
    },
  );

  testWidgets('valid scoped Library routes render their route-owned scope', (
    tester,
  ) async {
    final host = createHost();
    final router = host.container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: host.container,
        child: const _RouterHost(),
      ),
    );
    await loadAppearance(tester, host.api);

    for (final testCase in <({String path, String title})>[
      (path: '/library/platforms/nintendo_gb', title: 'Library · nintendo_gb'),
      (path: '/library/sources/source-1', title: 'Library · Source source-1'),
      (
        path: '/library/library-roots/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        title: 'Library · Root aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
    ]) {
      router.go(testCase.path);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, testCase.path);
      expect(find.text(testCase.title), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('library-search')),
        findsOneWidget,
      );
      expect(
        find.text('Scoped Library browsing is not available yet'),
        findsNothing,
      );
    }
  });

  testWidgets('invalid scoped Library route data remains a controlled error', (
    tester,
  ) async {
    final host = createHost();
    final router = host.container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: host.container,
        child: const _RouterHost(),
      ),
    );
    await loadAppearance(tester, host.api);
    router.go('/library/platforms/not-a-platform');
    await tester.pumpAndSettle();

    expect(find.text('Invalid Library scope'), findsOneWidget);
    expect(find.text('Page not found'), findsNothing);
    expect(
      router.routeInformationProvider.value.uri.path,
      '/library/platforms/not-a-platform',
    );
  });

  testWidgets('unknown paths use a bounded sanitized not-found surface', (
    tester,
  ) async {
    final host = createHost();
    final router = host.container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: host.container,
        child: const _RouterHost(),
      ),
    );
    await loadAppearance(tester, host.api);
    router.go('/missing?secret=do-not-show#fragment');
    await tester.pumpAndSettle();

    expect(find.text('Page not found'), findsOneWidget);
    expect(find.textContaining('/missing'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    expect(find.textContaining('fragment'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);

    await tester.tap(find.text('Go to Library'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/library');
  });

  testWidgets('unimplemented future paths still use the controlled not-found '
      'surface', (tester) async {
    final host = createHost();
    final router = host.container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: host.container,
        child: const _RouterHost(),
      ),
    );
    await loadAppearance(tester, host.api);

    for (final path in <String>[
      '/more',
      '/startup',
      '/collections',
      '/games',
      '/game-detail',
      '/diagnostics',
    ]) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(find.text('Page not found'), findsOneWidget, reason: path);
    }
  });

  testWidgets('stateful branches restore prior locations and canonicalize '
      'on active reselection', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    final host = createHost(
      sources: FakeSourcesApi(
        roots: [
          fakeRoot(
            id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            displayName: 'Games',
          ),
        ],
      ),
    );
    final router = host.container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: host.container,
        child: const _RouterHost(),
      ),
    );
    await loadAppearance(tester, host.api);

    const rootPath = '/sources/roots/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    router.go(rootPath);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, rootPath);

    await tester.tap(find.text('Settings'));
    await tester.pump();
    if (host.api.readRequests.isNotEmpty &&
        !host.api.readRequests.last.isCompleted) {
      host.api.readRequests.last.complete(
        const AppearanceSettings(themeMode: ThemeMode.light),
      );
    }
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/settings');

    // Switching back to Sources restores that branch's prior location.
    await tester.tap(find.text('Sources'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(router.routeInformationProvider.value.uri.path, rootPath);

    // Reselecting the active Sources destination canonicalizes to /sources.
    await tester.tap(find.text('Sources'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(router.routeInformationProvider.value.uri.path, '/sources');

    // Jobs keeps an independent branch.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Jobs'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(router.routeInformationProvider.value.uri.path, '/jobs');
    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Jobs'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(router.routeInformationProvider.value.uri.path, '/jobs');
  });

  testWidgets('Sources renders the configured-root landing and opens detail', (
    tester,
  ) async {
    final host = createHost(
      sources: FakeSourcesApi(
        roots: [
          fakeRoot(
            id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            displayName: 'Games',
          ),
        ],
      ),
    );
    final router = host.container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: host.container,
        child: const _RouterHost(),
      ),
    );
    await loadAppearance(tester, host.api);
    router.go('/sources');
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/sources');
    expect(find.text('Games'), findsOneWidget);
    expect(find.text('Never scanned'), findsOneWidget);

    await tester.tap(find.text('Games'));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/sources/roots/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    expect(find.text('Remove Library Folder'), findsOneWidget);
  });

  testWidgets('malformed root route data renders the distinguishable '
      'invalid-location surface', (tester) async {
    final host = createHost();
    final router = host.container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: host.container,
        child: const _RouterHost(),
      ),
    );
    await loadAppearance(tester, host.api);
    router.go('/sources/roots/not-an-id');
    await tester.pumpAndSettle();

    expect(find.text('Invalid location'), findsOneWidget);
    expect(find.text('Page not found'), findsNothing);
    expect(find.textContaining('not-an-id'), findsOneWidget);
    // Route state remains at the malformed location; no silent redirect.
    expect(
      router.routeInformationProvider.value.uri.path,
      '/sources/roots/not-an-id',
    );

    await tester.tap(find.text('Go to Sources'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/sources');
  });

  testWidgets('a valid but missing root canonicalizes through authoritative '
      'state', (tester) async {
    final host = createHost();
    final router = host.container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: host.container,
        child: const _RouterHost(),
      ),
    );
    await loadAppearance(tester, host.api);
    router.go('/sources/roots/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/sources');
    expect(find.text('No library folders yet'), findsOneWidget);
  });

  testWidgets(
    'resizing keeps one router location while shell presentation adapts',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(480, 800);
      addTearDown(tester.view.reset);

      final host = createHost();
      final router = host.container.read(appRouterProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: host.container,
          child: const _RouterHost(),
        ),
      );
      await loadAppearance(tester, host.api);

      for (final testCase in <({double width, Key key})>[
        (width: 480, key: const ValueKey<String>('compact-navigation-bar')),
        (width: 720, key: const ValueKey<String>('medium-navigation-rail')),
        (
          width: 1024,
          key: const ValueKey<String>('expanded-navigation-sidebar'),
        ),
        (width: 1440, key: const ValueKey<String>('large-navigation-sidebar')),
      ]) {
        tester.view.physicalSize = Size(testCase.width, 800);
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/library');
        expect(find.byKey(testCase.key), findsOneWidget);
        expect(find.bySemanticsLabel('Library'), findsOneWidget);
      }
    },
  );

  testWidgets('routed shell remains usable at representative text scales', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );

    for (final testCase in <({double width, String key})>[
      (width: 480, key: 'compact-navigation-bar'),
      (width: 1440, key: 'large-navigation-sidebar'),
    ]) {
      for (final scale in <double>[1, 2]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(testCase.width, 800);
        tester.binding.platformDispatcher.textScaleFactorTestValue = scale;

        final host = createHost();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: host.container,
            child: const _RouterHost(),
          ),
        );
        await loadAppearance(tester, host.api);

        expect(find.byKey(ValueKey<String>(testCase.key)), findsOneWidget);
        expect(find.bySemanticsLabel('Library'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Each scale is intentionally isolated in its own provider container;
        // unmount it here so auto-dispose scheduling cannot outlive the case.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        host.container.dispose();
      }
    }
  });

  testWidgets(
    'onboarding page owns its single authoritative read after routing admission',
    (tester) async {
      final onboarding = FakeLibraryOnboardingApi(_incompleteOnboardingState());
      final host = createHost(
        onboarding: onboarding,
        readiness: ApplicationPresentationReadiness.onboardingRequired,
      );
      final router = host.container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: host.container,
          child: const _RouterHost(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.path,
        '/onboarding/library',
      );
      expect(onboarding.getStateCalls, 1);
    },
  );

  testWidgets(
    'ready shell switches branches while the Library initial read is unresolved',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pendingLibraryRead = Completer<GamePage>();
      final reads = FakeLibraryReads()
        ..onListGames = (_) => pendingLibraryRead.future;
      final host = createHost(reads: reads);
      final router = host.container.read(appRouterProvider);
      addTearDown(() {
        if (!pendingLibraryRead.isCompleted) {
          pendingLibraryRead.complete(const GamePage(items: []));
        }
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: host.container,
          child: const _RouterHost(),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tapAt(const Offset(36, 52));
      await tester.pump();
      expect(router.routeInformationProvider.value.uri.path, '/sources');

      await tester.tapAt(const Offset(36, 96));
      await tester.pump();
      expect(router.routeInformationProvider.value.uri.path, '/jobs');

      await tester.tapAt(const Offset(36, 140));
      await tester.pump();
      expect(router.routeInformationProvider.value.uri.path, '/settings');

      await tester.tapAt(const Offset(36, 8));
      await tester.pump();
      expect(router.routeInformationProvider.value.uri.path, '/library');
      expect(host.onboarding.getStateCalls, 0);
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

final class _RouterMetadataSettingsApi implements MetadataSettingsApi {
  @override
  Future<MetadataSettings> getMetadataSettings() => Future.value(
    const MetadataSettings(preferredRegions: [], preferredLanguages: []),
  );

  @override
  Future<MetadataProviderSettings> getMetadataProviderSettings() =>
      Future.value(const MetadataProviderSettings(enabledProviders: []));

  @override
  Future<MetadataSettingsUpdateResult> updateMetadataSettings(
    MetadataSettings settings,
  ) => Future.value(
    MetadataSettingsUpdateResult.committedNoResolutionWork(settings),
  );

  @override
  Future<MetadataProviderSettingsUpdateResult> updateMetadataProviderSettings(
    MetadataProviderSettings settings,
  ) => Future.value(
    MetadataProviderSettingsUpdateResult.committedNoResolutionWork(settings),
  );
}

final class _RouterMetadataProvidersApi implements MetadataProvidersApi {
  @override
  Future<List<MetadataProviderReadiness>> listMetadataProviderReadiness() =>
      Future.value(const []);

  @override
  Future<ProviderCredentialReadiness> setMetadataProviderCredential({
    required String providerId,
    required List<int> credentialInput,
  }) => throw UnsupportedError('Router test provider setup is not focused');

  @override
  Future<ProviderCredentialReadiness> removeMetadataProviderCredential(
    String providerId,
  ) => throw UnsupportedError('Router test provider setup is not focused');
}

class _RouterHost extends ConsumerWidget {
  const _RouterHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      theme: ArgusTheme.light,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
