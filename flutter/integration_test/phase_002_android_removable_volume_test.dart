import 'dart:io';

import 'package:argus/app/bootstrap/app_bootstrap.dart';
import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/core/client/client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import 'phase_002_android_test_support.dart';

/// Focused removable-volume identity scenario.
///
/// The host script supplies a real StorageManager provider-volume identity.
/// This test uses only the opaque browse location, records the authoritative
/// LibraryRootId, and verifies that the same identity is available after the
/// host unmounts and remounts the same physical volume.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const mode = String.fromEnvironment('ARGUS_PHASE_002_REMOVABLE_MODE');
  const expectedProviderId = String.fromEnvironment(
    'ARGUS_ANDROID_REMOVABLE_EXPECTED_PROVIDER_ID',
  );
  const evidencePath = String.fromEnvironment(
    'ARGUS_PHASE_002_REMOVABLE_EVIDENCE_PATH',
  );

  if (mode != 'before' && mode != 'after') {
    throw StateError('Removable-volume mode must be before or after');
  }
  if (evidencePath.isEmpty) {
    throw StateError('Removable-volume evidence path is required');
  }

  testWidgets('removable volume preserves provider identity and root ID', (
    tester,
  ) async {
    await tester.pumpWidget(const ArgusBootstrap());
    await completePhase002LibraryOnboarding(tester);
    await _pumpUntil(
      tester,
      phase002ApplicationShellFinder(),
      message: 'Android shell did not become ready',
    );

    final facts = await _readRemovableFacts();
    final fact = facts.firstWhere(
      (value) =>
          expectedProviderId.isEmpty ||
          value['providerVolumeId'] == expectedProviderId,
      orElse: () =>
          fail('Expected removable StorageManager identity was not mounted'),
    );
    expect(fact['isRemovable'], isTrue);
    expect(fact['providerVolumeId'], isA<String>());
    expect(fact['transientMountPath'], isA<String>());
    final providerVolumeId = fact['providerVolumeId']! as String;
    final transientMountPath = fact['transientMountPath']! as String;

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ArgusApp)),
      listen: false,
    );
    final client = container.read(argusClientProvider);
    final browseRoots = await client.sources.listLocalFilesystemBrowseRoots();
    final browseRoot = browseRoots.firstWhere(
      (root) => root.displayName == fact['safeDisplayName'],
      orElse: () => fail('Removable StorageManager root is not browseable'),
    );
    expect(
      browseRoot.location.value,
      isNot(contains('/')),
      reason: 'provider browse identity must not be a raw mount path',
    );

    if (mode == 'before') {
      final result = await client.sources.addLocalLibraryRoot(
        LocalFilesystemRootSelection.providerSelection(
          browseRoot.location.value,
        ),
      );
      final rootId = switch (result) {
        AddLocalLibraryRootResultAdded(:final root) => root.id,
        AddLocalLibraryRootResultAlreadyConfigured(
          :final existingLibraryRootId,
        ) =>
          existingLibraryRootId,
        AddLocalLibraryRootResultOverlapsExisting(
          :final existingLibraryRootId,
        ) =>
          existingLibraryRootId,
      };
      final roots = await client.sources.listLibraryRoots(
        offset: 0,
        pageSize: 100,
      );
      expect(roots.items.any((root) => root.id == rootId), isTrue);
      expect(
        roots.items.firstWhere((root) => root.id == rootId).availability,
        LibraryRootAvailability.available,
      );
      await File(evidencePath).writeAsString(
        <String>[
          rootId.value,
          providerVolumeId,
          transientMountPath,
          'true',
        ].join('\n'),
      );
      return;
    }

    final evidence = await File(evidencePath).readAsLines();
    expect(evidence.length, greaterThanOrEqualTo(4));
    expect(evidence[1], providerVolumeId);
    expect(evidence[2], isNotEmpty);
    expect(evidence[3], 'true');
    final expectedRootId = evidence.first;
    final roots = await client.sources.listLibraryRoots(
      offset: 0,
      pageSize: 100,
    );
    final root = roots.items.firstWhere(
      (value) => value.id.value == expectedRootId,
      orElse: () =>
          fail('Existing LibraryRootId was not restored after remount'),
    );
    expect(root.availability, LibraryRootAvailability.available);
    expect(
      (await client.jobs.listActiveJobs()).items,
      isEmpty,
      reason: 'trustworthy remount must not auto-resume work',
    );
  });
}

Future<List<Map<Object?, Object?>>> _readRemovableFacts() async {
  const channel = MethodChannel('argus/local_filesystem_platform');
  final raw = await channel.invokeMethod<List<Object?>>('readMountedVolumes');
  return (raw ?? const <Object?>[])
      .whereType<Map<Object?, Object?>>()
      .where((fact) => fact['isRemovable'] == true)
      .toList(growable: false);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  required String message,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail(message);
}
