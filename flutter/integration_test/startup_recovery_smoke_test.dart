import 'dart:io';

import 'package:argus/core/bridge/bridge.dart';
import 'package:argus/core/client/client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Real native proof for the FE-005 failed-startup recovery path: a
/// correctly-migrated temporary database with a missing appearance-settings
/// aggregate makes the first `initialize()` return typed `StartupFailed`
/// through Rust -> FRB -> ArgusClient; advertised recovery actions, technical
/// details, sanitized diagnostics export, and the certified targeted reset
/// are then exercised against the real runtime.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real startup failure offers recovery, details, export, and reset',
    (tester) async {
      final fixture = Directory.systemTemp.createTempSync(
        'argus-startup-recovery-smoke-',
      );
      final gateway = FrbArgusClientGateway(
        dataDirectoryOverride: fixture.path,
      );
      final client = ArgusClient(gateway: gateway);

      try {
        debugPrint('seeding database');
        await _seedMigratedDatabaseWithMissingSettings(fixture.path);
        debugPrint('seeded; initializing');

        final initial = await client.initialize();
        debugPrint('initialize returned ${initial.runtimeType}');
        expect(initial, isA<RuntimeStateStartupFailed>());
        final failed = initial as RuntimeStateStartupFailed;
        expect(failed.runtimeInstanceId.isValid, isTrue);
        expect(failed.failure.phase, StartupPhase.settingsInitialization);
        expect(
          failed.failure.error.code.value,
          'ARGUS.V1.CONFIGURATION.PERSISTED_SETTINGS_INVALID',
        );
        final advertised = failed.failure.recoveryActions
            .map((action) => action.kind)
            .toSet();
        expect(
          advertised,
          containsAll(<RecoveryActionKind>[
            RecoveryActionKind.resetAppearanceSettings,
            RecoveryActionKind.retryStartup,
            RecoveryActionKind.exportDiagnostics,
            RecoveryActionKind.copyTechnicalDetails,
            RecoveryActionKind.openDataDirectory,
            RecoveryActionKind.exit,
          ]),
        );

        debugPrint('loading technical details');
        final details = await client.diagnostics.startupTechnicalDetails(
          failed.runtimeInstanceId,
        );
        debugPrint('technical details loaded');
        expect(details.text, isNotEmpty);
        expect(details.text, contains('lifecycle=StartupFailed'));

        final exportDestination = '${fixture.path}/argus-diagnostics.zip';
        debugPrint('exporting diagnostics');
        final export = await client.diagnostics.exportStartupDiagnostics(
          failed.runtimeInstanceId,
          exportDestination,
        );
        debugPrint('export complete');
        expect(export.outcome, DiagnosticsExportOutcome.created);
        final archive = File(exportDestination);
        expect(archive.existsSync(), isTrue);
        expect(archive.lengthSync(), greaterThan(0));

        debugPrint('resetting appearance settings');
        final replacement = await client.runtime.resetAppearanceSettings(
          failed.runtimeInstanceId,
        );
        debugPrint('reset complete');
        expect(replacement, isA<RuntimeStateReady>());
        final ready = replacement as RuntimeStateReady;
        expect(ready.runtimeInstanceId, isNot(failed.runtimeInstanceId));
        debugPrint('assertions complete');
      } finally {
        debugPrint('shutting down replacement runtime');
        await client.runtime.generalShutdown().timeout(
          const Duration(seconds: 30),
        );
        debugPrint('shutdown complete');
        await client.dispose().timeout(const Duration(seconds: 30));
        debugPrint('client disposed');
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

Future<void> _seedMigratedDatabaseWithMissingSettings(
  String dataDirectory,
) async {
  final migrationSql =
      Platform.environment['ARGUS_MIGRATION_SQL'] ?? await _readMigrationSql();
  final checksum =
      Platform.environment['ARGUS_MIGRATION_SHA256'] ??
      await _sha256(_migrationFilePath());

  final sql =
      '''
CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  kind TEXT NOT NULL,
  checksum TEXT NOT NULL,
  applied_at TEXT NOT NULL,
  app_version TEXT NOT NULL
);
INSERT INTO schema_migrations (version, name, kind, checksum, applied_at, app_version)
VALUES (1, '0001_initial', 'sql', '$checksum', '1720000000', '0.1.0');
$migrationSql
DELETE FROM appearance_settings WHERE singleton_key = 1;
''';
  final db = sqlite3.sqlite3.open('$dataDirectory/argus.sqlite3');
  try {
    db.execute(sql);
  } finally {
    db.dispose();
  }
}

String _migrationFilePath() {
  final repositoryRoot =
      Platform.environment['ARGUS_REPO_ROOT'] ?? '${Directory.current.path}/..';
  return '$repositoryRoot/rust/crates/argus-infrastructure/src/sqlite/'
      'migrations/sql/0001_initial.sql';
}

Future<String> _readMigrationSql() async {
  final file = File(_migrationFilePath());
  expect(file.existsSync(), isTrue, reason: file.path);
  return String.fromCharCodes(file.readAsBytesSync());
}

Future<String> _sha256(String path) async {
  final result = await Process.run('shasum', <String>['-a', '256', path]);
  expect(result.exitCode, 0, reason: 'shasum failed: ${result.stderr}');
  final output = (result.stdout as String).trim();
  return output.split(RegExp(r'\s+')).first;
}
