import 'package:argus/app/routing/app_destination.dart';
import 'package:argus/app/routing/app_router.dart';
import 'package:argus/app/routing/app_routes.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/core/design_system/argus_theme.dart';
import 'package:argus/features/settings/application/appearance_settings_dependencies.dart';
import 'package:argus/features/settings/application/appearance_settings_state.dart';
import 'package:argus/features/sources/sources_composition.dart';
import 'package:argus/features/sources/application/sources_state.dart';
import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/settings/appearance_settings_test_fakes.dart';
import '../../features/sources/sources_test_fakes.dart';

void main() {
  test('typed Settings route and semantic mapping are canonical', () {
    expect(const SettingsRoute().location, '/settings');
    expect(const SourcesRoute().location, '/sources');
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
  })
  createHost({FakeSourcesApi? sources}) {
    final api = FakeSettingsApi();
    final sourcesApi = sources ?? FakeSourcesApi();
    final container = ProviderContainer(
      overrides: [
        appearanceSettingsApiProvider.overrideWithValue(api),
        appearanceRuntimeContextProvider.overrideWith(
          (ref) => ref.watch(appearanceRuntimeContextHostProvider),
        ),
        sourcesApiProvider.overrideWithValue(sourcesApi),
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
    return (container: container, api: api, sourcesApi: sourcesApi);
  }

  Future<void> loadAppearance(WidgetTester tester, FakeSettingsApi api) async {
    await tester.pump();
    api.readRequests.single.complete(
      const AppearanceSettings(themeMode: ThemeMode.light),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('root redirects to Settings and renders the Settings page', (
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

    expect(router.routeInformationProvider.value.uri.path, '/settings');
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
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

    await tester.tap(find.text('Go to Settings'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/settings');
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
      '/library',
      '/collections',
      '/jobs',
      '/game-detail',
      '/diagnostics',
    ]) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(find.text('Page not found'), findsOneWidget, reason: path);
    }
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
        (width: 480, key: const ValueKey<String>('compact-more-button')),
        (width: 720, key: const ValueKey<String>('medium-navigation-rail')),
        (
          width: 1024,
          key: const ValueKey<String>('expanded-navigation-sidebar'),
        ),
        (width: 1440, key: const ValueKey<String>('large-navigation-sidebar')),
      ]) {
        tester.view.physicalSize = Size(testCase.width, 800);
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/settings');
        expect(find.byKey(testCase.key), findsOneWidget);
        expect(find.bySemanticsLabel('Settings'), findsOneWidget);
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
      (width: 480, key: 'compact-more-button'),
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
        expect(find.bySemanticsLabel('Settings'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
  });
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
