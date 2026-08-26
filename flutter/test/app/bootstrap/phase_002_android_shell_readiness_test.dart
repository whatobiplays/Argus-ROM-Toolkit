import 'package:argus/app/routing/app_destination.dart';
import 'package:argus/app/shell/application_shell.dart';
import 'package:argus/core/design_system/argus_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/phase_002_android_test_support.dart';

Future<void> pumpAdaptiveShell(
  WidgetTester tester, {
  required double width,
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
              currentDestination: AppDestination.library,
              onLibrarySelected: () {},
              onSettingsSelected: () {},
              onSourcesSelected: () {},
              onJobsSelected: () {},
              child: const Center(child: Text('route child')),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Phase 002 shell readiness accepts compact NavigationBar', (
    tester,
  ) async {
    await pumpAdaptiveShell(tester, width: 480);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(phase002ApplicationShellFinder(), findsOneWidget);
  });

  testWidgets('Phase 002 shell readiness accepts expanded NavigationRail', (
    tester,
  ) async {
    await pumpAdaptiveShell(tester, width: 1024);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(phase002ApplicationShellFinder(), findsOneWidget);
  });

  testWidgets('Phase 002 shell readiness rejects unrelated not-ready UI', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const Text('Loading'),
          bottomNavigationBar: NavigationBar(
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );

    expect(phase002ApplicationShellFinder(), findsNothing);
  });
}
