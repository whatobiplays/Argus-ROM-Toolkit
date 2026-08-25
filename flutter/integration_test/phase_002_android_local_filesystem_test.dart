import 'package:argus/app/bootstrap/app_bootstrap.dart';
import 'package:argus/core/client/client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'phase_002_android_test_support.dart';

/// P02-002 Android root-management proof.
///
/// The repository-owned harness creates the fixture at
/// `/sdcard/ArgusP02002Fixture` before launching this test. The test uses the
/// production Android composition and the Argus-owned browser from the real
/// mounted-volume discovery through root-only add, restart, duplicate and
/// overlap handling, and removal. It never uses a platform file picker or
/// reads the fixture directly from Dart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const mode = String.fromEnvironment('ARGUS_PHASE_002_MODE');
  if (mode != 'seed' && mode != 'verify') {
    throw StateError(
      'ARGUS_PHASE_002_MODE must be "seed" or "verify", got: $mode',
    );
  }

  testWidgets('Android local-filesystem browser proves root-only management', (
    tester,
  ) async {
    await tester.pumpWidget(const ArgusBootstrap());
    final client = await completePhase002LibraryOnboarding(tester);
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey<String>('compact-navigation-bar')),
      message: 'Android application shell did not become ready',
    );

    final baselineJobCount = await _jobCount(client);
    await _goToSources(tester);
    if (mode == 'seed') {
      _assertNoScanControls(tester);
    } else {
      await _pumpUntil(
        tester,
        find.byKey(const ValueKey<String>('sources-scan-all')),
        message: 'Scan All did not appear once the configured root exists',
      );
    }

    switch (mode) {
      case 'seed':
        await _runSeedScenario(tester, client, baselineJobCount);
      case 'verify':
        await _runVerifyScenario(tester, client, baselineJobCount);
    }
  });
}

Future<void> _runSeedScenario(
  WidgetTester tester,
  ArgusClient client,
  int baselineJobCount,
) async {
  final browseRoots = await client.sources.listLocalFilesystemBrowseRoots();
  expect(browseRoots, isNotEmpty, reason: 'StorageManager found no roots');
  final primary = browseRoots.first;
  final rootPage = await client.sources.listLocalFilesystemBrowseDirectories(
    location: primary.location,
    pageSize: 100,
  );
  final fixture = rootPage.directories.firstWhere(
    (directory) => directory.displayName == 'ArgusP02002Fixture',
    orElse: () => fail(
      'primary browse root did not expose the repository fixture directory',
    ),
  );
  final childPage = await client.sources.listLocalFilesystemBrowseDirectories(
    location: fixture.location,
    pageSize: 100,
  );
  expect(
    childPage.directories.map((directory) => directory.displayName),
    contains('Child'),
  );

  await _selectFixtureFolder(tester, primary, fixture);
  await _pumpUntil(
    tester,
    find.text('Add Library Folder?'),
    message: 'folder selection confirmation did not appear',
  );
  expect(
    find.byKey(const ValueKey<String>('add-folder-and-scan')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey<String>('add-folder-without-scan')),
    findsOneWidget,
  );
  expect(
    find.textContaining('/storage/emulated/0'),
    findsNothing,
    reason: 'Android mount paths must not become Sources UI copy',
  );
  await tester.tap(
    find.byKey(const ValueKey<String>('add-folder-without-scan')),
  );

  var roots = await _waitForRoots(client, 1);
  expect(roots.single.availability, LibraryRootAvailability.available);
  await _pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('sources-remove-library-folder')),
    message: 'root detail did not appear after root-only add',
  );
  await _goToSources(tester);
  await _pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('sources-scan-all')),
    message: 'Scan All did not appear on the Sources landing',
  );
  expect(
    await _jobCount(client),
    baselineJobCount,
    reason: 'root-only add created a job',
  );
}

Future<void> _runVerifyScenario(
  WidgetTester tester,
  ArgusClient client,
  int baselineJobCount,
) async {
  var roots = await _waitForRoots(client, 1);
  final rootId = roots.single.id;
  expect(roots.single.id, rootId);
  expect(roots.single.availability, LibraryRootAvailability.available);

  // Re-selecting the same opaque provider identity is idempotent and does
  // not create a second configured root.
  final restartedRoots = await client.sources.listLocalFilesystemBrowseRoots();
  final restartedPrimary = restartedRoots.first;
  final restartedFixturePage = await client.sources
      .listLocalFilesystemBrowseDirectories(
        location: restartedPrimary.location,
        pageSize: 100,
      );
  final restartedFixture = restartedFixturePage.directories.firstWhere(
    (directory) => directory.displayName == 'ArgusP02002Fixture',
  );
  await _selectFixtureFolder(tester, restartedPrimary, restartedFixture);
  await _pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('add-folder-without-scan')),
    message: 'duplicate selection confirmation did not appear',
  );
  await tester.tap(
    find.byKey(const ValueKey<String>('add-folder-without-scan')),
  );
  await _pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('sources-remove-library-folder')),
    message: 'duplicate selection did not redirect to the existing root',
  );
  roots = await _waitForRoots(client, 1);
  expect(roots.single.id, rootId);

  // Selecting the containing primary volume exercises the typed overlap
  // outcome without exposing or interpreting its opaque identity in Dart.
  await _goToSources(tester);
  await tester.tap(
    find.byKey(const ValueKey<String>('sources-add-library-folder')),
  );
  await _pumpUntil(
    tester,
    find.byKey(
      ValueKey<String>('local-browser-root-${restartedPrimary.location.value}'),
    ),
    message: 'Argus browser did not show the primary volume',
  );
  await tester.tap(
    find.byKey(
      ValueKey<String>('local-browser-root-${restartedPrimary.location.value}'),
    ),
  );
  await _pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('local-browser-select-folder')),
    message: 'primary volume browse page did not load',
  );
  await tester.ensureVisible(
    find.byKey(const ValueKey<String>('local-browser-select-folder')),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('local-browser-select-folder')),
  );
  await _pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('add-folder-without-scan')),
    message: 'overlap confirmation did not appear',
  );
  await tester.tap(
    find.byKey(const ValueKey<String>('add-folder-without-scan')),
  );
  await _pumpUntil(
    tester,
    find.text('This folder overlaps an existing configured Library Folder.'),
    message: 'typed overlap outcome was not rendered',
  );
  expect(await _waitForRoots(client, 1), hasLength(1));
  await tester.tap(find.text('Open existing folder'));
  await _pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('sources-remove-library-folder')),
    message: 'overlap redirect did not return to the existing root',
  );

  await tester.tap(
    find.byKey(const ValueKey<String>('sources-remove-library-folder')),
  );
  await _pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('remove-root-confirm')),
    message: 'root removal confirmation did not appear',
  );
  await tester.tap(find.byKey(const ValueKey<String>('remove-root-confirm')));
  await _waitForRoots(client, 0);
  expect(
    await _jobCount(client),
    baselineJobCount,
    reason: 'root management created a job',
  );
}

Future<void> _goToSources(WidgetTester tester) async {
  final addButton = find
      .byKey(const ValueKey<String>('sources-add-library-folder'))
      .hitTestable();
  if (addButton.evaluate().isNotEmpty) {
    return;
  }
  final sources = find
      .descendant(
        of: find.byKey(const ValueKey<String>('compact-navigation-bar')),
        matching: find.text('Sources'),
      )
      .hitTestable();
  await tester.tap(sources);
  await _pumpUntil(tester, addButton, message: 'Sources page did not appear');
}

void _assertNoScanControls(WidgetTester tester) {
  expect(find.byKey(const ValueKey<String>('sources-scan-all')), findsNothing);
}

Future<void> _selectFixtureFolder(
  WidgetTester tester,
  LocalFilesystemBrowseRoot primary,
  LocalFilesystemBrowseDirectory fixture,
) async {
  await tester.tap(
    find.byKey(const ValueKey<String>('sources-add-library-folder')),
  );
  final rootKey = ValueKey<String>(
    'local-browser-root-${primary.location.value}',
  );
  await _pumpUntil(
    tester,
    find.byKey(rootKey),
    message: 'Argus browser did not show the mounted primary volume',
  );
  await tester.tap(find.byKey(rootKey));
  final fixtureKey = ValueKey<String>(
    'local-browser-directory-${fixture.location.value}',
  );
  await _pumpUntil(
    tester,
    find.byKey(fixtureKey),
    message: 'Argus browser did not show the fixture directory',
  );
  await tester.tap(find.byKey(fixtureKey));
  await _pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('local-browser-up')),
    message: 'Argus browser did not load the fixture location',
  );
  await tester.tap(find.byKey(const ValueKey<String>('local-browser-up')));
  await _pumpUntil(
    tester,
    find.byKey(fixtureKey),
    message: 'browser Up did not return to the primary volume',
  );
  await tester.tap(find.byKey(fixtureKey));
  await _pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('local-browser-up')),
    message: 'browser did not re-open the fixture location',
  );
  await tester.tap(
    find.byKey(const ValueKey<String>('local-browser-select-folder')),
  );
}

Future<List<LibraryRoot>> _waitForRoots(
  ArgusClient client,
  int expected,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (true) {
    final page = await client.sources.listLibraryRoots(
      offset: 0,
      pageSize: 100,
    );
    if (page.totalCount == expected) return page.items;
    if (DateTime.now().isAfter(deadline)) {
      fail('configured root count never reached $expected');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<int> _jobCount(ArgusClient client) async {
  final active = await client.jobs.listActiveJobs();
  final terminal = await client.jobs.listRecentTerminalJobs(
    offset: 0,
    pageSize: 20,
  );
  return active.totalCount + terminal.totalCount;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  required String message,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) fail(message);
    await tester.pump(const Duration(milliseconds: 100));
  }
}
