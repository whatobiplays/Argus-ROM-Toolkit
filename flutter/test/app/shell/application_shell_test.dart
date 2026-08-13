import 'package:argus/app/routing/app_destination.dart';
import 'package:argus/app/routing/app_routes.dart';
import 'package:argus/app/shell/application_shell.dart';
import 'package:argus/core/design_system/argus_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpShell(
  WidgetTester tester, {
  required double width,
  AppDestination? currentDestination = AppDestination.settings,
  VoidCallback? onSettingsSelected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ArgusTheme.light,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: SizedBox(
          width: width,
          height: 800,
          child: ApplicationShell(
            currentDestination: currentDestination,
            onSettingsSelected: onSettingsSelected ?? () {},
            child: const Center(child: Text('route child')),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('production exposes only the Settings semantic destination', () {
    expect(AppDestination.values, <AppDestination>[AppDestination.settings]);
    expect(destinationForUri(Uri.parse('/settings')), AppDestination.settings);
    expect(destinationForUri(Uri.parse('/unknown')), isNull);
  });

  for (final testCase in <({double width, Key key})>[
    (width: 480, key: const ValueKey<String>('compact-more-button')),
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
    expect(find.byType(BottomAppBar), findsOneWidget);
    expect(find.byTooltip('More'), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
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
    expect(find.text('route child'), findsOneWidget);

    await pumpShell(tester, width: 1440);
    final largeRail = tester.widget<NavigationRail>(
      find.byType(NavigationRail),
    );
    expect(largeRail.extended, isTrue);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('route child'), findsOneWidget);
  });

  testWidgets('Compact More is transient and selects Settings', (tester) async {
    var selectionCount = 0;
    await pumpShell(
      tester,
      width: 480,
      onSettingsSelected: () => selectionCount++,
    );

    expect(find.byTooltip('More'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('compact-more-button')));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(selectionCount, 0);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(selectionCount, 1);
  });

  testWidgets('Compact More is keyboard-operable and dismissible', (
    tester,
  ) async {
    var selectionCount = 0;
    await pumpShell(
      tester,
      width: 480,
      onSettingsSelected: () => selectionCount++,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(selectionCount, 1);
  });

  testWidgets('Compact More dismisses with Escape without a keyboard trap', (
    tester,
  ) async {
    var selectionCount = 0;
    await pumpShell(
      tester,
      width: 480,
      onSettingsSelected: () => selectionCount++,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsNothing);
    expect(selectionCount, 0);

    // The modal returns focus to More, so ordinary activation remains usable.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(selectionCount, 0);
  });

  testWidgets('Compact More meets the normal interactive target baseline', (
    tester,
  ) async {
    await pumpShell(tester, width: 480);

    final size = tester.getSize(
      find.byKey(const ValueKey<String>('compact-more-button')),
    );
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
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

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(selectionCount, width == 720 ? 1 : 2);
      }
    },
  );

  testWidgets('navigation actions expose meaningful semantics', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await pumpShell(tester, width: 480);
      expect(find.bySemanticsLabel('More'), findsOneWidget);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Settings'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await pumpShell(tester, width: 720);
      expect(
        tester.getSemantics(find.text('Settings')).label,
        contains('Settings'),
      );
    } finally {
      semanticsHandle.dispose();
    }
  });
}
