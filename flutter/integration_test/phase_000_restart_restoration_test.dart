import 'dart:io';

import 'package:argus/app/bootstrap/app_bootstrap.dart';
import 'package:argus/app/bootstrap/application_presentation.dart';
import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/core/bridge/bridge.dart';
import 'package:argus/core/client/client.dart' as client;
import 'package:argus/features/settings/settings.dart';
import 'package:argus/features/settings/settings_composition.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Test-owned environment input selecting the restart phase.
const String _restartModeEnvironment = 'ARGUS_PHASE_000_RESTART_MODE';

/// Test-owned environment input selecting the shared isolated data directory.
const String _dataDirectoryEnvironment = 'ARGUS_PHASE_000_DATA_DIR';

/// Real two-native-process Phase 000 restart proof.
///
/// One test target is invoked twice by the native milestone harness as two
/// distinct `flutter test ... -d macos` processes. The `seed` phase launches
/// the real production bootstrap against an isolated temporary data directory,
/// changes Theme Mode to Dark through the real Settings control, waits for the
/// authoritative backend read to confirm Dark, and shuts the native runtime
/// down normally. The `verify` phase launches a second native process against
/// the same data directory and proves the first normal Settings shell frame is
/// already Dark, with no earlier normal shell under a System/bootstrap theme.
///
/// Neither phase deletes the shared data directory; the harness owns that
/// cleanup. Both phases fail immediately when the required environment input
/// is missing or invalid.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final mode = Platform.environment[_restartModeEnvironment];
  final dataDirectory = Platform.environment[_dataDirectoryEnvironment];
  if (mode != 'seed' && mode != 'verify') {
    throw StateError(
      '$_restartModeEnvironment must be "seed" or "verify", got: $mode',
    );
  }
  if (dataDirectory == null ||
      dataDirectory.isEmpty ||
      !dataDirectory.startsWith('/')) {
    throw StateError(
      '$_dataDirectoryEnvironment must be an absolute directory path',
    );
  }
  final directory = Directory(dataDirectory);
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }

  switch (mode) {
    case 'seed':
      _runSeedPhase(dataDirectory);
    case 'verify':
      _runVerifyPhase(dataDirectory);
  }
}

void _runSeedPhase(String dataDirectory) {
  testWidgets('seed process persists Dark through the real Settings workflow', (
    tester,
  ) async {
    await _runPhase(
      tester,
      dataDirectory,
      assertions: (tester, container) async {
        await _pumpUntil(
          tester,
          condition: () => _shellVisible(tester),
          message: 'Seed phase: normal Settings shell did not appear',
          container: container,
        );

        final rootClient = container.read(argusClientProvider);
        expect(_rootThemeIs(tester, ThemeMode.system), isTrue);
        final initial = await rootClient.settings.getAppearanceSettings();
        expect(initial.themeMode, client.ThemeMode.system);

        await tester.tap(find.text('Dark'));
        await tester.pump();

        await _pumpUntil(
          tester,
          condition: () =>
              _rootThemeIs(tester, ThemeMode.dark) &&
              find.text('Saving appearance settings…').evaluate().isEmpty,
          message:
              'Seed phase: Dark confirmation did not settle after mutation',
          container: container,
        );

        expect(_rootThemeIs(tester, ThemeMode.dark), isTrue);
        final persisted = await rootClient.settings.getAppearanceSettings();
        expect(persisted.themeMode, client.ThemeMode.dark);
      },
    );
  });
}

void _runVerifyPhase(String dataDirectory) {
  testWidgets(
    'verify process proves the first normal shell is Dark after restart',
    (tester) async {
      await _runPhase(
        tester,
        dataDirectory,
        assertions: (tester, container) async {
          // Inspect the frame produced by the initial pumpWidget first, then
          // inspect immediately after every individual pump. Every frame with
          // a normal shell must already be Dark; the timeout only guards
          // against a native startup that never completes.
          var admissionRecorded = false;
          final deadline = DateTime.now().add(const Duration(seconds: 60));
          while (!admissionRecorded) {
            if (_shellVisible(tester)) {
              expect(_rootThemeIs(tester, ThemeMode.dark), isTrue);
              final settingsContext = tester.element(find.byType(SettingsPage));
              expect(Theme.of(settingsContext).brightness, Brightness.dark);
              admissionRecorded = true;
            } else {
              if (DateTime.now().isAfter(deadline)) {
                _dumpVisibleState(tester, container);
                fail(
                  'Verify phase: first normal shell did not appear within '
                  '60 seconds',
                );
              }
              await tester.pump(const Duration(milliseconds: 20));
            }
          }

          final rootClient = container.read(argusClientProvider);
          final persisted = await rootClient.settings.getAppearanceSettings();
          expect(persisted.themeMode, client.ThemeMode.dark);
        },
      );
    },
  );
}

/// Runs one restart phase and guarantees clean native teardown.
///
/// The root [ArgusClient] is captured explicitly so teardown can await
/// `generalShutdown()` and then `dispose()` before the widget tree is
/// replaced; the later ProviderScope teardown is then an idempotent no-op for
/// the already-closed client. A body failure is re-thrown after teardown so
/// the teardown cannot mask the original diagnostic.
Future<void> _runPhase(
  WidgetTester tester,
  String dataDirectory, {
  required Future<void> Function(
    WidgetTester tester,
    ProviderContainer container,
  )
  assertions,
}) async {
  final container = await _pumpRealApp(tester, dataDirectory);
  Object? bodyError;
  StackTrace? bodyStack;
  try {
    await assertions(tester, container);
  } catch (error, stackTrace) {
    bodyError = error;
    bodyStack = stackTrace;
  }
  final teardownError = await _shutDownAndDetach(tester, container);
  if (bodyError != null) {
    Error.throwWithStackTrace(bodyError, bodyStack!);
  }
  if (teardownError != null) {
    Error.throwWithStackTrace(teardownError, StackTrace.current);
  }
}

/// Pumps the real production bootstrap with the test-owned data directory.
Future<ProviderContainer> _pumpRealApp(
  WidgetTester tester,
  String dataDirectory,
) async {
  await tester.pumpWidget(
    ArgusBootstrap(
      clientGatewayFactory: () =>
          FrbArgusClientGateway(dataDirectoryOverride: dataDirectory),
    ),
  );
  return ProviderScope.containerOf(
    tester.element(find.byType(ArgusApp)),
    listen: false,
  );
}

/// Pumps one frame at a time until [condition] holds.
///
/// The condition is checked before every pump, so a frame that satisfies it
/// is never skipped. The timeout is failure protection only; it is never the
/// synchronization condition.
Future<void> _pumpUntil(
  WidgetTester tester, {
  required ProviderContainer container,
  required bool Function() condition,
  required String message,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      _dumpVisibleState(tester, container);
      fail('$message (timed out after ${timeout.inSeconds} seconds)');
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Prints the visible UI and composition state when a phase times out.
///
/// The dump is failure diagnostics only; it never changes the assertions or
/// the synchronization conditions.
void _dumpVisibleState(WidgetTester tester, ProviderContainer container) {
  final visibleTexts = find
      .byType(Text)
      .evaluate()
      .map((element) => (element.widget as Text).data)
      .whereType<String>()
      .toList();
  debugPrint('Visible text widgets at timeout: $visibleTexts');
  debugPrint(
    'SettingsPage count at timeout: '
    '${find.byType(SettingsPage).evaluate().length}',
  );
  debugPrint(
    'Startup state at timeout: '
    '${container.read(startupControllerProvider)}',
  );
  debugPrint(
    'Appearance state at timeout: '
    '${container.read(appearanceSettingsControllerProvider)}',
  );
  debugPrint(
    'Presentation readiness at timeout: '
    '${container.read(applicationPresentationReadinessProvider)}',
  );
}

bool _shellVisible(WidgetTester tester) =>
    find.byType(SettingsPage).evaluate().isNotEmpty;

bool _rootThemeIs(WidgetTester tester, ThemeMode mode) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode == mode;

/// Shuts the native runtime down, disposes the root client, then detaches.
///
/// Returns the first teardown failure so callers can decide whether it masks a
/// body failure. The tree replacement happens only after both awaits complete.
Future<Object?> _shutDownAndDetach(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final rootClient = container.read(argusClientProvider);
  Object? teardownError;
  try {
    await rootClient.runtime.generalShutdown().timeout(
      const Duration(seconds: 30),
    );
  } catch (error) {
    teardownError = error;
  }
  try {
    await rootClient.dispose().timeout(const Duration(seconds: 30));
  } catch (error) {
    teardownError ??= error;
  }
  await tester.pumpWidget(const SizedBox.shrink());
  return teardownError;
}
