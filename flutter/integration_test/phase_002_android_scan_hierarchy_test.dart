import 'dart:io';

import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/app_bootstrap.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/core/client/client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// P02-003 Android single-root scan, reconciliation, hierarchy, and Jobs
/// proof.
///
/// The repository-owned shell harness creates and mutates the fixture between
/// terminal phases. The test always selects the fixture through the
/// production Argus browser and reads scan, hierarchy, and job state through
/// the typed client APIs. The fixture path and the harness evidence path are
/// never configured as a durable Argus root identity or rendered Sources
/// copy.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const mode = String.fromEnvironment('ARGUS_PHASE_002_MODE');
  const evidencePath = String.fromEnvironment('ARGUS_PHASE_002_EVIDENCE_PATH');
  if (!<String>{'seed', 'reconcile', 'cancel', 'retry'}.contains(mode)) {
    throw StateError(
      'ARGUS_PHASE_002_MODE must be seed, reconcile, cancel, or retry; '
      'got: $mode',
    );
  }
  if (evidencePath.isEmpty || !evidencePath.startsWith('/')) {
    throw StateError('ARGUS_PHASE_002_EVIDENCE_PATH must be an absolute path');
  }

  testWidgets('Android P02-003 scan and hierarchy milestone', (tester) async {
    await tester.pumpWidget(const ArgusBootstrap());
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey<String>('compact-navigation-bar')),
      message: 'Android application shell did not become ready',
    );

    final container = _container(tester);
    final client = container.read(argusClientProvider);
    switch (mode) {
      case 'seed':
        await _runSeed(tester, client, evidencePath);
      case 'reconcile':
        await _runReconcile(tester, client, evidencePath);
      case 'cancel':
        await _runCancel(tester, client, evidencePath);
      case 'retry':
        await _runRetry(tester, client, evidencePath);
    }
  });
}

Future<void> _runSeed(
  WidgetTester tester,
  ArgusClient client,
  String evidencePath,
) async {
  final (primary, fixture) = await _findFixture(client);
  final childPage = await client.sources.listLocalFilesystemBrowseDirectories(
    location: fixture.location,
    pageSize: 100,
  );
  expect(
    childPage.directories.map((directory) => directory.displayName),
    contains('Nested'),
  );

  await _selectFixtureFolder(tester, primary, fixture);
  await _pumpUntil(
    tester,
    find.text('Add Library Folder?'),
    message: 'fixture selection confirmation did not appear',
  );
  expect(
    find.byKey(const ValueKey<String>('add-folder-and-scan')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey<String>('add-folder-without-scan')),
    findsOneWidget,
  );
  expect(find.byKey(const ValueKey<String>('sources-scan-all')), findsNothing);
  expect(
    find.textContaining('/storage/emulated/0'),
    findsNothing,
    reason: 'transient Android mount paths must not become Sources copy',
  );
  await tester.tap(
    find.byKey(const ValueKey<String>('add-folder-and-scan')).hitTestable(),
  );

  final roots = await _waitForRoots(client, 1);
  final root = roots.single;
  expect(root.availability, LibraryRootAvailability.available);
  expect(
    root.safeLocationPresentation,
    contains('ArgusP02003Fixture'),
    reason: 'Add & Scan must use the selected fixture directory',
  );
  expect(root.safeLocationPresentation, isNot(contains('/storage/')));
  final scanJobId = await _waitForRootLastScan(
    client,
    root.id,
    status: LibraryRootLastScanStatus.complete,
  );
  final job = await client.jobs.getJob(JobRunId(scanJobId));
  expect(job.job.lifecycleState, JobLifecycleState.completed);

  await _openConfiguredRoot(tester, client, root);
  await _pumpUntil(
    tester,
    find.text('Nested'),
    message: 'initial source hierarchy did not render Nested',
  );
  await _pumpUntil(
    tester,
    find.text('move-me.bin'),
    message: 'initial source hierarchy did not render move-me.bin',
  );
  expect(find.byKey(const ValueKey<String>('sources-scan-all')), findsNothing);

  final rootChildren = await _rootChildren(client, root.id);
  final moved = _entryByName(rootChildren, 'move-me.bin');
  expect(
    _entryNames(rootChildren),
    containsAll(<String>['Nested', 'keep.txt', 'remove-me.bin', 'move-me.bin']),
  );
  File(evidencePath).writeAsStringSync(moved.sourceEntryId.value);
}

Future<void> _runReconcile(
  WidgetTester tester,
  ArgusClient client,
  String evidencePath,
) async {
  final seedEntryId = File(evidencePath).readAsStringSync().trim();
  expect(seedEntryId, hasLength(32));

  final roots = await _waitForRoots(client, 1);
  final root = roots.single;
  final previousJobId = root.lastScan?.jobRunId;
  expect(previousJobId, isNotNull);
  await _openConfiguredRoot(tester, client, root);
  await _pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('sources-start-scan')),
    message: 'existing root did not expose Scan Again',
  );
  expect(find.text('Scan Again'), findsOneWidget);
  await tester.tap(
    find.byKey(const ValueKey<String>('sources-start-scan')).hitTestable(),
  );

  final completedJobId = await _waitForRootLastScan(
    client,
    root.id,
    status: LibraryRootLastScanStatus.complete,
    previousJobId: previousJobId,
  );
  expect(completedJobId, isNot(previousJobId));

  final afterRescan = await _rootChildren(client, root.id);
  expect(_entryNames(afterRescan), contains('added.bin'));
  expect(_entryNames(afterRescan), isNot(contains('remove-me.bin')));
  final movedDirectory = _entryByName(afterRescan, 'Moved');
  final movedChildren = await client.sources.listSourceEntryChildren(
    libraryRootId: root.id,
    parentSourceEntryId: movedDirectory.sourceEntryId,
    pageSize: 100,
  );
  final moved = _entryByName(movedChildren.items, 'move-me.bin');
  expect(moved.sourceEntryId.value, seedEntryId);
  expect(find.byKey(const ValueKey<String>('sources-scan-all')), findsNothing);

  await _openConfiguredRoot(tester, client, root);
  await _pumpUntil(
    tester,
    find.text('Moved'),
    message: 'reconciled source hierarchy did not render Moved',
  );
}

Future<void> _runCancel(
  WidgetTester tester,
  ArgusClient client,
  String evidencePath,
) async {
  final roots = await _waitForRoots(client, 1);
  final root = roots.single;
  final previousJobId = root.lastScan?.jobRunId;
  expect(previousJobId, isNotNull);
  await _openConfiguredRoot(tester, client, root);
  await _pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('sources-start-scan')),
    message: 'cancel phase root did not expose Scan Again',
  );
  await tester.tap(
    find.byKey(const ValueKey<String>('sources-start-scan')).hitTestable(),
  );

  final jobRunId = await _waitForActiveLibraryScan(client, previousJobId);
  await _waitUntilCanCancel(client, jobRunId);
  final cancellation = await client.jobs.cancelJob(JobRunId(jobRunId));
  expect(cancellation, CancelJobResult.cancellationRequested);
  await _waitForJobLifecycle(client, jobRunId, JobLifecycleState.cancelled);
  final cancelled = await client.jobs.getJob(JobRunId(jobRunId));
  expect(cancelled.job.lifecycleState, JobLifecycleState.cancelled);
  expect(cancelled.job.cancellationRequested, isTrue);

  final afterCancel = await _rootChildren(client, root.id);
  expect(_entryNames(afterCancel), containsAll(<String>['keep.txt', 'Moved']));
  File(evidencePath).writeAsStringSync(jobRunId);
  expect(find.byKey(const ValueKey<String>('sources-scan-all')), findsNothing);
}

Future<void> _runRetry(
  WidgetTester tester,
  ArgusClient client,
  String evidencePath,
) async {
  final cancelledJobId = File(evidencePath).readAsStringSync().trim();
  expect(cancelledJobId, hasLength(32));
  final historicalBefore = await client.jobs.getJob(JobRunId(cancelledJobId));
  expect(historicalBefore.job.lifecycleState, JobLifecycleState.cancelled);
  expect(historicalBefore.job.controls.canRetry, isTrue);

  final roots = await _waitForRoots(client, 1);
  final root = roots.single;
  await _openConfiguredRoot(tester, client, root);
  await _pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('sources-view-last-job')),
    message: 'cancelled root did not expose its historical job',
  );
  await tester.tap(
    find.byKey(const ValueKey<String>('sources-view-last-job')).hitTestable(),
  );
  await _pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('jobs-retry-job')),
    message: 'cancelled historical job did not expose Retry',
  );
  final retry = await client.jobs.retryJob(JobRunId(cancelledJobId));
  expect(retry, isA<RetryJobResultAdmitted>());

  final successorJobId = await _waitForRetrySuccessor(
    client,
    JobRunId(cancelledJobId),
  );
  expect(successorJobId, isNot(cancelledJobId));
  final successor = await client.jobs.getJob(JobRunId(successorJobId));
  expect(successor.job.lifecycleState, isNot(JobLifecycleState.cancelled));
  final historicalAfter = await client.jobs.getJob(JobRunId(cancelledJobId));
  expect(historicalAfter.job.lifecycleState, JobLifecycleState.cancelled);
  expect(historicalAfter.job.controls.canRetry, isFalse);

  await _waitForJobLifecycle(
    client,
    successorJobId,
    JobLifecycleState.completed,
  );
  final completedRoot = (await _waitForRoots(client, 1)).single;
  expect(completedRoot.lastScan?.jobRunId, successorJobId);
  expect(completedRoot.lastScan?.status, LibraryRootLastScanStatus.complete);

  await _openConfiguredRoot(tester, client, completedRoot);
  await _pumpUntil(
    tester,
    find.text('Moved'),
    message: 'retry hierarchy did not return authoritative Moved entry',
  );
  expect(find.byKey(const ValueKey<String>('sources-scan-all')), findsNothing);
}

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(ArgusApp)),
  listen: false,
);

Future<(LocalFilesystemBrowseRoot, LocalFilesystemBrowseDirectory)>
_findFixture(ArgusClient client) async {
  final roots = await client.sources.listLocalFilesystemBrowseRoots();
  expect(roots, isNotEmpty, reason: 'StorageManager found no browse roots');
  for (final primary in roots) {
    final page = await client.sources.listLocalFilesystemBrowseDirectories(
      location: primary.location,
      pageSize: 100,
    );
    for (final directory in page.directories) {
      if (directory.displayName == 'ArgusP02003Fixture') {
        return (primary, directory);
      }
    }
  }
  fail('no mounted volume exposed ArgusP02003Fixture');
}

Future<void> _selectFixtureFolder(
  WidgetTester tester,
  LocalFilesystemBrowseRoot primary,
  LocalFilesystemBrowseDirectory fixture,
) async {
  await _goToSources(tester);
  await tester.tap(
    find.byKey(const ValueKey<String>('sources-add-library-folder')),
  );
  final rootKey = ValueKey<String>(
    'local-browser-root-${primary.location.value}',
  );
  await _pumpUntil(
    tester,
    find.byKey(rootKey),
    message: 'Argus browser did not show the mounted volume',
  );
  await tester.tap(find.byKey(rootKey).hitTestable());
  final fixtureKey = ValueKey<String>(
    'local-browser-directory-${fixture.location.value}',
  );
  await _pumpUntil(
    tester,
    find.byKey(fixtureKey),
    message: 'Argus browser did not show the fixture directory',
  );
  await tester.tap(find.byKey(fixtureKey).hitTestable());
  await _pumpUntilAbsent(
    tester,
    find.byKey(fixtureKey),
    message: 'Argus browser did not enter ArgusP02003Fixture',
  );
  await _pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('local-browser-select-folder')),
    message: 'Argus browser did not open the fixture location',
  );
  await tester.tap(
    find.byKey(const ValueKey<String>('local-browser-select-folder')),
  );
}

Future<void> _openConfiguredRoot(
  WidgetTester tester,
  ArgusClient client,
  LibraryRoot root,
) async {
  await _goToSources(tester);
  await _pumpUntil(
    tester,
    find.text(root.displayName).hitTestable(),
    message: 'configured root did not appear in Sources',
  );
  await tester.tap(find.text(root.displayName).hitTestable().first);
  await _pumpUntil(
    tester,
    find.byKey(const ValueKey<String>('sources-remove-library-folder')),
    message: 'configured root detail did not appear',
  );
  final current = await client.sources.getLibraryRoot(root.id);
  expect(current.id, root.id);
}

Future<void> _goToSources(WidgetTester tester) async {
  final addButton = find
      .byKey(const ValueKey<String>('sources-add-library-folder'))
      .hitTestable();
  if (addButton.evaluate().isNotEmpty) return;
  await tester.tap(
    find
        .descendant(
          of: find.byKey(const ValueKey<String>('compact-navigation-bar')),
          matching: find.text('Sources'),
        )
        .hitTestable(),
  );
  await _pumpUntil(tester, addButton, message: 'Sources page did not appear');
}

Future<List<LibraryRoot>> _waitForRoots(
  ArgusClient client,
  int expected,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 120));
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

Future<List<SourceEntry>> _rootChildren(
  ArgusClient client,
  LibraryRootId rootId,
) async {
  final page = await client.sources.listSourceEntryChildren(
    libraryRootId: rootId,
    pageSize: 200,
  );
  return page.items;
}

Future<String> _waitForActiveLibraryScan(
  ArgusClient client,
  String? previousJobId,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 120));
  while (true) {
    final active = await client.jobs.listActiveJobs();
    for (final item in active.items) {
      if (item.operationType == 'library_scan' &&
          item.jobRunId.value != previousJobId) {
        return item.jobRunId.value;
      }
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('single-root Scan Again did not expose an active library scan');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> _waitUntilCanCancel(ArgusClient client, String jobRunId) async {
  final deadline = DateTime.now().add(const Duration(seconds: 180));
  while (true) {
    final detail = await client.jobs.getJob(JobRunId(jobRunId));
    if (detail.job.controls.canCancel) return;
    if (detail.job.lifecycleState.isTerminal) {
      fail(
        'single-root scan reached ${detail.job.lifecycleState} before '
        'canCancel became available',
      );
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('single-root scan never exposed canCancel within 180 seconds');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> _waitForJobLifecycle(
  ArgusClient client,
  String jobRunId,
  JobLifecycleState expected,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 240));
  while (true) {
    final detail = await client.jobs.getJob(JobRunId(jobRunId));
    if (detail.job.lifecycleState == expected) return;
    if (detail.job.lifecycleState.isTerminal) {
      fail(
        'job $jobRunId reached ${detail.job.lifecycleState} instead of '
        '$expected',
      );
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('job $jobRunId did not reach $expected within 240 seconds');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<String> _waitForRetrySuccessor(
  ArgusClient client,
  JobRunId historicalJobRunId,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 120));
  while (true) {
    final detail = await client.jobs.getJob(historicalJobRunId);
    final scanDetail = switch (detail.operationDetail) {
      OperationDetailLibraryScan(:final detail) => detail,
    };
    final successor = scanDetail.retrySuccessorJobRunId;
    if (successor != null) return successor.value;
    if (DateTime.now().isAfter(deadline)) {
      fail('cancelled historical job never exposed a retry successor');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<String> _waitForRootLastScan(
  ArgusClient client,
  LibraryRootId rootId, {
  required LibraryRootLastScanStatus status,
  String? previousJobId,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 240));
  while (true) {
    final root = await client.sources.getLibraryRoot(rootId);
    final lastScan = root.lastScan;
    if (lastScan != null && lastScan.jobRunId != previousJobId) {
      if (lastScan.status == status) return lastScan.jobRunId;
      final detail = await client.jobs.getJob(JobRunId(lastScan.jobRunId));
      final scanDetail = switch (detail.operationDetail) {
        OperationDetailLibraryScan(:final detail) => detail,
      };
      fail(
        'root $rootId reached last-scan ${lastScan.status} instead of '
        '$status; job=${detail.job.lifecycleState}; '
        'failure=${detail.job.boundedTerminalFailure}; '
        'progress=${scanDetail.progress}; runs=${scanDetail.scanRuns}',
      );
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('root $rootId last-scan never reached $status');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

SourceEntry _entryByName(List<SourceEntry> entries, String name) =>
    entries.firstWhere((entry) => entry.displayName == name);

List<String> _entryNames(List<SourceEntry> entries) => [
  for (final entry in entries) entry.displayName,
];

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  required String message,
  Duration timeout = const Duration(seconds: 120),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) fail(message);
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpUntilAbsent(
  WidgetTester tester,
  Finder finder, {
  required String message,
  Duration timeout = const Duration(seconds: 120),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) fail(message);
    await tester.pump(const Duration(milliseconds: 100));
  }
}
