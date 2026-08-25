import 'package:argus/app/routing/app_destination.dart';
import 'package:argus/app/routing/app_routes.dart';
import 'package:argus/app/shell/application_shell.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/core/design_system/argus_theme.dart';
import 'package:argus/features/jobs/jobs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Future<void> pumpShell(
  WidgetTester tester, {
  required double width,
  AppDestination? currentDestination = AppDestination.settings,
  VoidCallback? onSettingsSelected,
  VoidCallback? onSourcesSelected,
  VoidCallback? onJobsSelected,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ArgusTheme.light,
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: SizedBox(
            width: width,
            height: 800,
            child: ApplicationShell(
              currentDestination: currentDestination,
              onSettingsSelected: onSettingsSelected ?? () {},
              onSourcesSelected: onSourcesSelected ?? () {},
              onJobsSelected: onJobsSelected ?? () {},
              child: const Center(child: Text('route child')),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

GoRouter shellRouter(String initialLocation) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      ShellRoute(
        builder: (context, state, child) => BranchAwareShell(
          currentUri: state.uri,
          currentDestination: destinationForUri(state.uri),
          child: child,
        ),
        routes: <RouteBase>[
          GoRoute(
            path: '/sources',
            builder: (context, state) => const Scaffold(body: Text('sources')),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const Scaffold(body: Text('settings')),
          ),
          GoRoute(
            path: '/jobs',
            builder: (context, state) => const Scaffold(body: Text('jobs')),
          ),
          GoRoute(
            path: '/jobs/:jobRunId',
            builder: (context, state) =>
                const Scaffold(body: Text('job detail')),
          ),
        ],
      ),
    ],
  );
}

void main() {
  test('production exposes the implemented semantic destinations', () {
    expect(AppDestination.values, <AppDestination>[
      AppDestination.library,
      AppDestination.sources,
      AppDestination.jobs,
      AppDestination.settings,
    ]);
    expect(destinationForUri(Uri.parse('/library')), AppDestination.library);
    expect(destinationForUri(Uri.parse('/settings')), AppDestination.settings);
    expect(destinationForUri(Uri.parse('/sources')), AppDestination.sources);
    expect(destinationForUri(Uri.parse('/jobs')), AppDestination.jobs);
    expect(
      destinationForUri(Uri.parse('/jobs/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')),
      AppDestination.jobs,
    );
    expect(
      destinationForUri(
        Uri.parse('/sources/roots/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
      ),
      AppDestination.sources,
    );
    expect(destinationForUri(Uri.parse('/unknown')), isNull);
  });

  for (final testCase in <({double width, Key key})>[
    (width: 480, key: const ValueKey<String>('compact-navigation-bar')),
    (width: 720, key: const ValueKey<String>('medium-navigation-rail')),
    (width: 1024, key: const ValueKey<String>('expanded-navigation-sidebar')),
    (width: 1440, key: const ValueKey<String>('large-navigation-sidebar')),
  ]) {
    testWidgets('renders the ${testCase.width} adaptive shell structure', (
      tester,
    ) async {
      await pumpShell(tester, width: testCase.width);

      expect(find.byKey(testCase.key), findsOneWidget);
      expect(find.text('route child'), findsOneWidget);
    });
  }

  testWidgets('adaptive classes use the concrete navigation widgets', (
    tester,
  ) async {
    await pumpShell(tester, width: 480);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(BottomAppBar), findsNothing);
    expect(find.byTooltip('More'), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Jobs'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('route child'), findsOneWidget);

    await pumpShell(tester, width: 720);
    final mediumRail = tester.widget<NavigationRail>(
      find.byType(NavigationRail),
    );
    expect(mediumRail.extended, isFalse);
    expect(find.text('route child'), findsOneWidget);

    await pumpShell(tester, width: 1024);
    final expandedRail = tester.widget<NavigationRail>(
      find.byType(NavigationRail),
    );
    expect(expandedRail.extended, isTrue);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('route child'), findsOneWidget);

    await pumpShell(tester, width: 1440);
    final largeRail = tester.widget<NavigationRail>(
      find.byType(NavigationRail),
    );
    expect(largeRail.extended, isTrue);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('route child'), findsOneWidget);
  });

  testWidgets('Compact destinations are direct and select each destination', (
    tester,
  ) async {
    var sourcesSelectionCount = 0;
    var settingsSelectionCount = 0;
    var jobsSelectionCount = 0;
    await pumpShell(
      tester,
      width: 480,
      onSourcesSelected: () => sourcesSelectionCount++,
      onSettingsSelected: () => settingsSelectionCount++,
      onJobsSelected: () => jobsSelectionCount++,
    );

    // All three destinations are visible without opening any sheet.
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Jobs'), findsOneWidget);
    final bar = tester.widget<NavigationBar>(
      find.byKey(const ValueKey<String>('compact-navigation-bar')),
    );
    expect(bar.selectedIndex, 2);
    expect(bar.destinations, hasLength(3));
    expect(sourcesSelectionCount, 0);
    expect(settingsSelectionCount, 0);
    expect(jobsSelectionCount, 0);

    final barRect = tester.getRect(
      find.byKey(const ValueKey<String>('compact-navigation-bar')),
    );
    final destinationWidth = barRect.width / 3;
    await tester.tapAt(
      Offset(barRect.left + destinationWidth / 2, barRect.center.dy),
    );
    await tester.pump();
    // ignore: avoid_print
    print('DEBUG sources=$sourcesSelectionCount');
    expect(sourcesSelectionCount, 1);
    expect(settingsSelectionCount, 0);
    expect(jobsSelectionCount, 0);

    await tester.tapAt(
      Offset(barRect.left + destinationWidth * 2.5, barRect.center.dy),
    );
    // ignore: avoid_print
    print('DEBUG settings=$settingsSelectionCount');
    expect(settingsSelectionCount, 1);

    await tester.tapAt(
      Offset(barRect.left + destinationWidth * 1.5, barRect.center.dy),
    );
    // ignore: avoid_print
    print('DEBUG jobs=$jobsSelectionCount');
    expect(jobsSelectionCount, 1);
  });

  testWidgets('Compact NavigationBar is keyboard-operable', (tester) async {
    final selected = <String>{};
    await pumpShell(
      tester,
      width: 480,
      onSourcesSelected: () => selected.add('sources'),
      onSettingsSelected: () => selected.add('settings'),
    );

    // Tab and activate until at least two distinct destinations responded.
    for (var attempt = 0; attempt < 18 && selected.length < 2; attempt++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }

    expect(selected, containsAll(<String>['sources', 'settings']));
  });

  testWidgets('Compact destinations meet the normal interactive target '
      'baseline', (tester) async {
    await pumpShell(tester, width: 480);

    final bar = tester.getSize(
      find.byKey(const ValueKey<String>('compact-navigation-bar')),
    );
    expect(bar.height, greaterThanOrEqualTo(48));
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Jobs'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('Compact Jobs shows the active-count badge', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeJobSummaryControllerProvider.overrideWithValue(
            const AsyncValue<ActiveJobSummary>.data(
              ActiveJobSummary(activeCount: 2),
            ),
          ),
        ],
        child: MaterialApp(
          theme: ArgusTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(480, 800)),
            child: const SizedBox(
              width: 480,
              height: 800,
              child: ApplicationShell(
                currentDestination: AppDestination.jobs,
                onSettingsSelected: _noop,
                onSourcesSelected: _noop,
                onJobsSelected: _noop,
                child: Center(child: Text('route child')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets(
    'Compact Jobs preserves sole-active-job routing through BranchAwareShell',
    (tester) async {
      final runId = 'a' * 32;
      final router = shellRouter('/sources');
      addTearDown(router.dispose);
      tester.view.physicalSize = const Size(480, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeJobSummaryControllerProvider.overrideWithValue(
              AsyncValue<ActiveJobSummary>.data(
                ActiveJobSummary(
                  activeCount: 1,
                  soleActiveJobRunId: JobRunId(runId),
                ),
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      final barRect = tester.getRect(
        find.byKey(const ValueKey<String>('compact-navigation-bar')),
      );
      await tester.tapAt(
        Offset(barRect.left + barRect.width / 2, barRect.center.dy),
      );
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/jobs/$runId',
      );
    },
  );

  testWidgets('Compact destination reselection restores the saved branch', (
    tester,
  ) async {
    final runId = 'a' * 32;
    final router = shellRouter('/sources');
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(480, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeJobSummaryControllerProvider.overrideWithValue(
            AsyncValue<ActiveJobSummary>.data(
              ActiveJobSummary(
                activeCount: 1,
                soleActiveJobRunId: JobRunId(runId),
              ),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final barRect = tester.getRect(
      find.byKey(const ValueKey<String>('compact-navigation-bar')),
    );
    await tester.tapAt(
      Offset(barRect.left + barRect.width / 2, barRect.center.dy),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(
      Offset(barRect.left + barRect.width / 6, barRect.center.dy),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(
      Offset(barRect.left + barRect.width / 2, barRect.center.dy),
    );
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/jobs/$runId',
    );
  });

  testWidgets('wide navigation uses the route-derived Settings selection', (
    tester,
  ) async {
    var selectionCount = 0;
    for (final width in <double>[720, 1024, 1440]) {
      await pumpShell(
        tester,
        width: width,
        onSettingsSelected: () => selectionCount++,
      );

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pump();
    }

    expect(selectionCount, 3);
  });

  testWidgets('Compact destinations expose Material semantics', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await pumpShell(tester, width: 480);
      expect(find.bySemanticsLabel(RegExp('Sources')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Jobs')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Settings')), findsOneWidget);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets(
    'Medium and extended rail Settings destinations are keyboard-operable',
    (tester) async {
      var selectionCount = 0;

      for (final width in <double>[720, 1024]) {
        await pumpShell(
          tester,
          width: width,
          onSettingsSelected: () => selectionCount++,
        );

        for (var index = 0; index < 8 && selectionCount == 0; index++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
        }

        expect(selectionCount, 1);
      }
    },
  );

  testWidgets(
    'live width transitions preserve the current routed branch identity',
    (tester) async {
      final runId = 'a' * 32;
      final router = shellRouter('/jobs/$runId');
      addTearDown(router.dispose);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();

      for (final width in <double>[599, 600, 839, 840, 1199, 1200, 599]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpAndSettle();
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          '/jobs/$runId',
          reason: 'route changed while window width became $width',
        );
      }
    },
  );

  testWidgets('compact navigation remains usable at 2x text scale', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpShell(tester, width: 320);

    expect(tester.takeException(), isNull);
    for (final label in <String>['Sources', 'Jobs', 'Settings']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });
}

void _noop() {}
