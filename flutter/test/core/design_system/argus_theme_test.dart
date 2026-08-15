import 'package:argus/app/routing/app_destination.dart';
import 'package:argus/app/shell/application_shell.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/core/design_system/argus_theme.dart';
import 'package:argus/features/settings/application/appearance_settings_dependencies.dart';
import 'package:argus/features/settings/application/appearance_settings_state.dart';
import 'package:argus/features/settings/settings.dart';
import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/settings/appearance_settings_test_fakes.dart';

void main() {
  Future<void> pumpSurface(
    WidgetTester tester, {
    required ThemeData theme,
  }) async {
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1440, 800)),
            child: ApplicationShell(
              currentDestination: AppDestination.settings,
              onSettingsSelected: () {},
              onSourcesSelected: () {},
              onJobsSelected: () {},
              child: const SettingsPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    api.readRequests.single.complete(
      const AppearanceSettings(themeMode: ThemeMode.light),
    );
    await tester.pumpAndSettle();
  }

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

    await pumpSurface(tester, theme: ArgusTheme.light);

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

    await pumpSurface(tester, theme: ArgusTheme.dark);

    try {
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });
}
