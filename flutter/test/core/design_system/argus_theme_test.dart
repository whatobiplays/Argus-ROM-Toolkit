import 'package:argus/app/routing/app_destination.dart';
import 'package:argus/app/shell/application_shell.dart';
import 'package:argus/core/design_system/argus_theme.dart';
import 'package:argus/features/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light production theme uses Material 3', () {
    final theme = ArgusTheme.light;

    expect(theme.brightness, Brightness.light);
    expect(theme.useMaterial3, isTrue);
    expect(theme.visualDensity, VisualDensity.standard);
  });

  test('dark production theme uses Material 3', () {
    final theme = ArgusTheme.dark;

    expect(theme.brightness, Brightness.dark);
    expect(theme.useMaterial3, isTrue);
    expect(theme.visualDensity, VisualDensity.standard);
  });

  testWidgets('light production surface meets text contrast guidance', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: ArgusTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1440, 800)),
          child: ApplicationShell(
            currentDestination: AppDestination.settings,
            onSettingsSelected: () {},
            child: const SettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    try {
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('dark production surface meets text contrast guidance', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: ArgusTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1440, 800)),
          child: ApplicationShell(
            currentDestination: AppDestination.settings,
            onSettingsSelected: () {},
            child: const SettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    try {
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });
}
