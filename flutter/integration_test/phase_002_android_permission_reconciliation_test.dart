import 'dart:io';

import 'package:argus/app/bootstrap/app_bootstrap.dart';
import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/core/client/client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'phase_002_android_test_support.dart';

/// Focused All files access revoke/regrant scenario. Permission loss is an
/// availability transition only; the authoritative root identity and durable
/// state are checked after explicit regrant, with no automatic job restart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const mode = String.fromEnvironment('ARGUS_PHASE_002_PERMISSION_MODE');
  const evidencePath = String.fromEnvironment(
    'ARGUS_PHASE_002_PERMISSION_EVIDENCE_PATH',
  );
  const fixtureRootName = String.fromEnvironment(
    'ARGUS_PHASE_002_PERMISSION_ROOT',
    defaultValue: 'ArgusP02005PermissionRoot',
  );
  if (!{'snapshot', 'revoked', 'restored'}.contains(mode)) {
    throw StateError('Permission mode must be snapshot, revoked, or restored');
  }

  testWidgets('All files access transitions preserve durable root state', (
    tester,
  ) async {
    const channel = MethodChannel('argus/platform_readiness');
    if (mode == 'revoked') {
      await tester.pumpWidget(const ArgusBootstrap());
      await _pumpUntil(tester, find.text('Storage access required'));
      final snapshot = (await channel.invokeMapMethod<Object?, Object?>(
        'readSnapshot',
      ))!;
      expect(snapshot['allFilesAccessGranted'], isFalse);
      expect(
        find.byKey(const ValueKey<String>('compact-navigation-bar')),
        findsNothing,
      );
      return;
    }

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
    final client = container.read(argusClientProvider);
    var roots = await client.sources.listLibraryRoots(offset: 0, pageSize: 100);
    if (mode == 'snapshot' && roots.items.isEmpty) {
      final browseRoots = await client.sources.listLocalFilesystemBrowseRoots();
      final primary = browseRoots.first;
      final page = await client.sources.listLocalFilesystemBrowseDirectories(
        location: primary.location,
        pageSize: 100,
      );
      final fixture = page.directories.firstWhere(
        (value) => value.displayName == fixtureRootName,
        orElse: () => fail('Permission fixture directory was not browseable'),
      );
      await client.sources.addLocalLibraryRoot(
        LocalFilesystemRootSelection.providerSelection(fixture.location.value),
      );
      roots = await client.sources.listLibraryRoots(offset: 0, pageSize: 100);
    }
    expect(roots.items, isNotEmpty);
    final rootId = roots.items.first.id.value;
    if (mode == 'snapshot') {
      await File(evidencePath).writeAsString(rootId);
      return;
    }

    expect(await File(evidencePath).readAsString(), rootId);
    expect(roots.items.first.availability, LibraryRootAvailability.available);
    expect((await client.jobs.listActiveJobs()).items, isEmpty);
  });
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}
