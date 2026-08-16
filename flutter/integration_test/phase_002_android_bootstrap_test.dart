import 'dart:io';

import 'package:argus/app/bootstrap/app_bootstrap.dart';
import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/settings/settings_composition.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// P02-001 granted real-stack scenario: with All files access granted (and
/// notifications pre-granted on API 33+), the real Android composition must
/// reach Ready through the packaged FRB/Rust/SQLite stack, persist
/// appearance settings in the host-standard app-private database, expose
/// Compact Sources/Jobs/Settings navigation, and keep exactly one root
/// client/runtime generation.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('granted readiness boots the real stack with one runtime', (
    tester,
  ) async {
    const channel = MethodChannel('argus/platform_readiness');

    await tester.pumpWidget(const ArgusBootstrap());
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('compact-navigation-bar')),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ArgusApp)),
      listen: false,
    );
    final snapshot = (await channel.invokeMapMethod<Object?, Object?>(
      'readSnapshot',
    ))!;
    expect(snapshot['allFilesAccessGranted'], isTrue);

    final standardDirectory =
        snapshot['standardApplicationDataDirectory'] as String;
    expect(
      File('$standardDirectory/argus.sqlite3').existsSync(),
      isTrue,
      reason: 'host-standard database must exist after real startup',
    );

    final navigationBar = find.byKey(
      const ValueKey<String>('compact-navigation-bar'),
    );
    expect(navigationBar, findsOneWidget);
    for (final label in <String>['Sources', 'Jobs', 'Settings']) {
      expect(
        find.descendant(of: navigationBar, matching: find.text(label)),
        findsOneWidget,
        reason: label,
      );
    }

    final settingsApi = container.read(appearanceSettingsApiProvider);
    await settingsApi.updateAppearanceSettings(
      const AppearanceSettings(themeMode: ThemeMode.dark),
    );
    final persisted = await settingsApi.getAppearanceSettings();
    expect(persisted.themeMode, ThemeMode.dark);

    final clientBefore = container.read(argusClientProvider);
    final generationBefore = container.read(readyRuntimeInstanceIdProvider);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      identical(container.read(argusClientProvider), clientBefore),
      isTrue,
      reason: 'exactly one root client must stay active during the run',
    );
    expect(
      container.read(readyRuntimeInstanceIdProvider),
      generationBefore,
      reason: 'runtime generation must not be replaced during the run',
    );
  });
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}
