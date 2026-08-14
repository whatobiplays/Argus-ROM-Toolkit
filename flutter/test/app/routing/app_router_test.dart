import 'package:argus/app/routing/app_destination.dart';
import 'package:argus/app/routing/app_router.dart';
import 'package:argus/app/routing/app_routes.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/core/design_system/argus_theme.dart';
import 'package:argus/features/settings/application/appearance_settings_dependencies.dart';
import 'package:argus/features/settings/application/appearance_settings_state.dart';
import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/settings/appearance_settings_test_fakes.dart';

void main() {
  test('typed Settings route and semantic mapping are canonical', () {
    expect(const SettingsRoute().location, '/settings');
    expect(destinationForUri(Uri.parse('/settings')), AppDestination.settings);
    expect(
      destinationForUri(Uri.parse('/settings?source=test')),
      AppDestination.settings,
    );
    expect(destinationForUri(Uri.parse('/unknown')), isNull);
  });

  ({ProviderContainer container, FakeSettingsApi api}) createHost() {
    final api = FakeSettingsApi();
    final container = ProviderContainer(
      overrides: [
        appearanceSettingsApiProvider.overrideWithValue(api),
        appearanceRuntimeContextProvider.overrideWith(
          (ref) => ref.watch(appearanceRuntimeContextHostProvider),
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
    return (container: container, api: api);
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

  testWidgets('production graph exposes only root redirect and Settings', (
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

    for (final path in <String>[
      '/more',
      '/startup',
      '/library',
      '/collections',
      '/jobs',
      '/sources',
      '/game-detail',
      '/diagnostics',
    ]) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(find.text('Page not found'), findsOneWidget, reason: path);
    }
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
