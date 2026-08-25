import 'package:argus/core/bridge/bridge.dart';
import 'package:argus/core/client/client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Focused real Android diagnostics scenario.
///
/// Rust creates the failed-startup archive in its authoritative data root. The
/// only Flutter-side publication input is the no-argument native operation;
/// this test never receives an archive path or a content URI.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android diagnostics share uses the backend-owned artifact', (
    tester,
  ) async {
    const readinessChannel = MethodChannel('argus/platform_readiness');
    const shareChannel = MethodChannel('argus/diagnostics_share');
    final snapshot = (await readinessChannel.invokeMapMethod<Object?, Object?>(
      'readSnapshot',
    ))!;
    final standardDirectory = snapshot['standardApplicationDataDirectory'];
    expect(standardDirectory, isA<String>());
    final dataDirectory = standardDirectory! as String;

    final gateway = FrbArgusClientGateway(
      standardApplicationDataDirectory: dataDirectory,
      publishCompletedDiagnostics: () =>
          shareChannel.invokeMethod<void>('shareCompletedStartupDiagnostics'),
    );
    final client = ArgusClient(gateway: gateway);
    RuntimeState? initialized;

    try {
      initialized = await client.initialize();
      expect(initialized, isA<RuntimeStateStartupFailed>());
      final failed = initialized as RuntimeStateStartupFailed;
      final sharing = client.diagnosticsSharing;
      expect(sharing, isNotNull);

      final export = await sharing!.exportStartupDiagnosticsForSharing(
        failed.runtimeInstanceId,
      );
      expect(export.outcome, DiagnosticsExportOutcome.created);
      expect(export.destinationClassification, 'backend_owned_diagnostics');
    } finally {
      if (initialized case final RuntimeStateStartupFailed failed) {
        await client.runtime.exitFailedRuntime(failed.runtimeInstanceId);
      }
      await client.dispose();
    }
  });
}
