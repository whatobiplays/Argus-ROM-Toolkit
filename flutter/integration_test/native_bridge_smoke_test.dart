import 'dart:async';
import 'dart:io';

import 'package:argus/core/bridge/bridge.dart';
import 'package:argus/core/client/client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Real native smoke proof for the Phase 000 bridge: a real Rust host is
/// initialized through FRB, an appearance-settings round trip crosses the
/// bridge, and one payload-free change event reaches the Flutter client.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native bridge initializes, round-trips settings, and streams one event',
    (tester) async {
      final fixture = Directory.systemTemp.createTempSync(
        'argus-native-smoke-',
      );
      final gateway = FrbArgusClientGateway(
        dataDirectoryOverride: fixture.path,
      );
      final client = ArgusClient(gateway: gateway);
      final appearanceChanged = Completer<RuntimeEvent>();
      AppearanceSettings? original;
      final subscription = client.events.events.listen((event) {
        if (event.payload is RuntimeEventPayloadAppearanceSettingsChanged &&
            !appearanceChanged.isCompleted) {
          appearanceChanged.complete(event);
        }
      });

      try {
        final initial = await client.initialize();
        expect(initial, isA<RuntimeStateReady>());
        final ready = initial as RuntimeStateReady;
        expect(ready.runtimeInstanceId.isValid, isTrue);

        final before = await client.settings.getAppearanceSettings();
        original = before;
        final desired = before.themeMode == ThemeMode.light
            ? ThemeMode.dark
            : ThemeMode.light;
        await client.settings.updateAppearanceSettings(
          AppearanceSettings(themeMode: desired),
        );
        final after = await client.settings.getAppearanceSettings();
        expect(after.themeMode, desired);

        final event = await appearanceChanged.future.timeout(
          const Duration(seconds: 20),
        );
        expect(event.runtimeInstanceId, ready.runtimeInstanceId);
        expect(
          event.payload,
          isA<RuntimeEventPayloadAppearanceSettingsChanged>(),
        );
      } finally {
        try {
          if (original case final AppearanceSettings value) {
            await client.settings.updateAppearanceSettings(value);
          }
        } catch (_) {
          // Restoration is defensive; the primary result is preserved.
        }
        try {
          await client.runtime.generalShutdown();
        } catch (_) {
          // Shutdown is attempted even when restoration fails.
        }
        try {
          await subscription.cancel();
        } catch (_) {
          // Subscription cancellation must still run.
        }
        try {
          if (fixture.existsSync()) {
            fixture.deleteSync(recursive: true);
          }
        } catch (_) {
          // Temporary directory cleanup must still run.
        }
      }
    },
  );
}
