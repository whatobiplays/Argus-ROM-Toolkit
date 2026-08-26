import 'dart:io';

import 'package:argus/app/bootstrap/app_bootstrap.dart';
import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/core/client/client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'phase_002_android_test_support.dart';

/// Focused real-client multi-root and Scan All admission scenario.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const mode = String.fromEnvironment('ARGUS_PHASE_002_MULTI_ROOT_MODE');
  const rootA = String.fromEnvironment(
    'ARGUS_PHASE_002_MULTI_ROOT_A',
    defaultValue: 'ArgusP02005RootA',
  );
  const rootB = String.fromEnvironment(
    'ARGUS_PHASE_002_MULTI_ROOT_B',
    defaultValue: 'ArgusP02005RootB',
  );
  const fixtureRoot = String.fromEnvironment(
    'ARGUS_PHASE_002_MULTI_ROOT_FIXTURE_ROOT',
    defaultValue: 'ArgusP02005MultiRoot',
  );
  const evidencePath = String.fromEnvironment(
    'ARGUS_PHASE_002_MULTI_ROOT_EVIDENCE_PATH',
  );
  if (mode != 'seed' && mode != 'scan') {
    throw StateError('Multi-root mode must be seed or scan');
  }

  testWidgets('Android uses shared multi-root Scan All authority', (
    tester,
  ) async {
    await tester.pumpWidget(const ArgusBootstrap());
    await completePhase002LibraryOnboarding(tester);
    await _pumpUntil(tester, phase002ApplicationShellFinder());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ArgusApp)),
      listen: false,
    );
    final client = container.read(argusClientProvider);

    final browseRoots = await client.sources.listLocalFilesystemBrowseRoots();
    final primary = browseRoots.first;
    final primaryPage = await client.sources
        .listLocalFilesystemBrowseDirectories(
          location: primary.location,
          pageSize: 100,
        );
    final fixture = primaryPage.directories.firstWhere(
      (value) => value.displayName == fixtureRoot,
      orElse: () => fail('Fixture root $fixtureRoot was not browseable'),
    );
    final page = await client.sources.listLocalFilesystemBrowseDirectories(
      location: fixture.location,
      pageSize: 100,
    );
    if (mode == 'seed') {
      final selections = [rootA, rootB].map((name) {
        final directory = page.directories.firstWhere(
          (value) => value.displayName == name,
          orElse: () => fail('Fixture directory $name was not browseable'),
        );
        return LocalFilesystemRootSelection.providerSelection(
          directory.location.value,
        );
      });
      for (final selection in selections) {
        await client.sources.addLocalLibraryRoot(selection);
      }
      final roots = await client.sources.listLibraryRoots(
        offset: 0,
        pageSize: 100,
      );
      expect(roots.items, hasLength(2));
      await File(
        evidencePath,
      ).writeAsString(roots.items.map((root) => root.id.value).join('\n'));
      return;
    }

    final expectedIds = await File(evidencePath).readAsLines();
    final roots = await client.sources.listLibraryRoots(
      offset: 0,
      pageSize: 100,
    );
    expect(roots.items.map((root) => root.id.value), containsAll(expectedIds));
    final result = await client.sources.startLibraryScanAll(
      const ScanAllRequestIdentity('phase-002-android-scan-all'),
    );
    expect(result, isA<StartLibraryScanAllResultAdmitted>());
    final admitted = result as StartLibraryScanAllResultAdmitted;
    expect(
      admitted.admittedRoots,
      containsAll(expectedIds.map(LibraryRootId.new)),
    );
    final terminal = await _waitForTerminalJob(
      client,
      admitted.handle.jobRunId,
    );
    expect(terminal.job.lifecycleState.isTerminal, isTrue);
  });
}

Future<JobDetail> _waitForTerminalJob(
  ArgusClient client,
  JobRunId jobRunId,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    final detail = await client.jobs.getJob(jobRunId);
    if (detail.job.lifecycleState.isTerminal) return detail;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('Scan All job did not reach an authoritative terminal state');
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Android application shell did not become ready');
}
