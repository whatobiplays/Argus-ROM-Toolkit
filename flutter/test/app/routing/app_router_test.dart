import 'package:argus/app/routing/app_router.dart';
import 'package:argus/app/routing/app_routes.dart';
import 'package:argus/app/routing/app_destination.dart';
import 'package:argus/core/design_system/argus_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('root redirects to Settings and renders the static page', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _RouterHost(),
      ),
    );
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/settings');
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
  });

  testWidgets('direct Settings navigation renders Settings', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _RouterHost(),
      ),
    );
    router.go('/settings');
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/settings');
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
  });

  testWidgets('unknown paths use a bounded sanitized not-found surface', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _RouterHost(),
      ),
    );
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
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _RouterHost(),
      ),
    );

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

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const _RouterHost(),
        ),
      );
      await tester.pumpAndSettle();

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

        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const _RouterHost(),
          ),
        );
        await tester.pumpAndSettle();

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
