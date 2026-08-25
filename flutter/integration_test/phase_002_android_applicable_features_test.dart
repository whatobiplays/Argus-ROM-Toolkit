import 'package:argus/app/bootstrap/app_bootstrap.dart';
import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/features/sources/sources.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'phase_002_android_test_support.dart';

/// Focused production-composition proof for the Android-applicable feature
/// surface. Shared Rust Sources/Jobs authority is exercised through the real
/// client; this scenario does not duplicate admission or recovery logic.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android enables the existing Sources, Jobs, and diagnostics surface',
    (tester) async {
      await tester.pumpWidget(const ArgusBootstrap());
      await completePhase002LibraryOnboarding(tester);
      await _pumpUntil(
        tester,
        find.byKey(const ValueKey<String>('compact-navigation-bar')),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ArgusApp)),
        listen: false,
      );
      final sourcesCapabilities = container.read(
        sourcesPresentationCapabilitiesProvider,
      );
      final startupCapabilities = container.read(
        startupPresentationCapabilitiesProvider,
      );
      expect(sourcesCapabilities.singleRootScanExecution, isTrue);
      expect(sourcesCapabilities.scanAllExecution, isTrue);
      expect(sourcesCapabilities.activeRootCancelAndRemove, isTrue);
      expect(sourcesCapabilities.localFilesystemBrowser, isTrue);
      expect(startupCapabilities.diagnosticsExport, isTrue);
      expect(startupCapabilities.diagnosticsSharing, isTrue);
      expect(startupCapabilities.openDataDirectory, isFalse);

      final client = container.read(argusClientProvider);
      await client.sources.listLibraryRoots(offset: 0, pageSize: 100);
      await client.jobs.listActiveJobs();
    },
  );
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Android application shell did not become ready');
}
