import 'dart:io';

import 'package:argus/app/bootstrap/app_bootstrap.dart';
import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/core/bridge/bridge.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/sources/application/root_detail_controller.dart';
import 'package:argus/features/sources/application/root_list_controller.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Test-owned environment inputs for the Phase 001 native milestone.
const String _dataDirectoryEnvironment = 'ARGUS_PHASE_001_DATA_DIR';
const String _rootOneEnvironment = 'ARGUS_PHASE_001_ROOT_ONE';
const String _rootTwoEnvironment = 'ARGUS_PHASE_001_ROOT_TWO';

/// Real macOS Phase 001 composition proof.
///
/// The harness owns creation and cleanup of the isolated application-data
/// directory and the two temporary library roots. This target fails
/// immediately when any required input is missing or invalid and never falls
/// back to normal Argus or user-library locations. Folder selection flows
/// through the approved narrow [ArgusBootstrap.libraryFolderPicker] seam, so
/// the real Sources workflow is exercised from selection acceptance onward.
///
/// Workflow actions invoke the same application controllers the UI buttons
/// call (for example [SourcesRootDetailController.startScan] is exactly what
/// the Scan Again button invokes). Pointer-level taps are used where they are
/// deterministic in the native window (navigation, add-flow dialogs, the
/// job-detail view button); bottom-row controls are driven through their
/// controllers because macOS native hit-testing of those controls is not
/// reliable in this harness. All assertions synchronize on authoritative
/// backend reads, never on sleeps.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final dataDirectory = Platform.environment[_dataDirectoryEnvironment];
  final rootOne = Platform.environment[_rootOneEnvironment];
  final rootTwo = Platform.environment[_rootTwoEnvironment];
  for (final entry in <String, String?>{
    _dataDirectoryEnvironment: dataDirectory,
    _rootOneEnvironment: rootOne,
    _rootTwoEnvironment: rootTwo,
  }.entries) {
    final value = entry.value;
    if (value == null ||
        value.isEmpty ||
        !value.startsWith('/') ||
        !Directory(value).existsSync()) {
      throw StateError(
        '${entry.key} must be an existing absolute directory path',
      );
    }
  }

  testWidgets('macOS Phase 001 milestone proves the canonical local sources '
      'workflow against test-owned state', (tester) async {
    await _runMilestone(tester, dataDirectory!, rootOne!, rootTwo!);
  });
}

Future<void> _runMilestone(
  WidgetTester tester,
  String dataDirectory,
  String rootOne,
  String rootTwo,
) async {
  // Deterministic window geometry keeps navigation and dialogs visible.
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  var nextSelection = rootOne;
  final container = await _pumpRealApp(
    tester,
    dataDirectory,
    picker: () async => LocalFilesystemRootSelection(nextSelection),
  );
  Object? bodyError;
  StackTrace? bodyStack;
  try {
    final client = container.read(argusClientProvider);
    await _waitForShell(tester, container);
    await _goToSources(tester, container);

    // Step 1: Add & Scan through the real workflow.
    await _runAddLibraryFolderFlow(
      tester,
      container,
      choiceKey: const ValueKey<String>('add-folder-and-scan'),
    );
    final rootOneId = await _onlyRootId(client);
    final firstScanJobId = await _waitForRootLastScan(
      client,
      rootOneId,
      status: LibraryRootLastScanStatus.complete,
    );

    // Real hierarchy presentation: representative committed entries (one
    // directory and one file) appear through the Sources hierarchy browser.
    // Exact identity/kind/reconciliation semantics stay authoritative-API
    // assertions below; this proves the UI renders committed hierarchy data.
    await _waitForText(tester, container, 'Sub');
    await _waitForText(tester, container, 'rom.bin');

    final firstChildren = await _rootChildren(client, rootOneId);
    _expectNames(
      firstChildren,
      containsAll(<String>[
        'Sub',
        'rom.bin',
        'keep.txt',
        'removed.bin',
        'moved.bin',
      ]),
    );
    final movedId = _entryById(firstChildren, 'moved.bin').sourceEntryId;
    expect(_entryById(firstChildren, 'Sub').kind, SourceEntryKind.directory);
    expect(_entryById(firstChildren, 'rom.bin').kind, SourceEntryKind.file);

    final firstJob = await client.jobs.getJob(JobRunId(firstScanJobId));
    final firstDetail = _scanDetail(firstJob);
    expect(firstJob.job.lifecycleState, JobLifecycleState.completed);
    expect(firstDetail.scanRuns, hasLength(1));
    expect(firstDetail.scanRuns.single.status, JobScanStatus.complete);
    expect(firstDetail.progress.entriesObserved, isNotNull);
    expect(firstDetail.progress.entriesObserved!, greaterThanOrEqualTo(6));
    expect(firstDetail.progress.entriesCommitted, isNotNull);
    expect(firstDetail.progress.entriesCommitted!, greaterThanOrEqualTo(6));

    // Jobs detail/progress is meaningful through the real UI.
    await tester.tap(
      find.byKey(const ValueKey<String>('sources-view-last-job')).hitTestable(),
    );
    await _waitForText(tester, container, 'Completed');
    expect(find.text('Library Scan'), findsOneWidget);
    expect(find.text('Roots requested: 1'), findsOneWidget);
    await _goToSources(tester, container);

    // Step 2: mutate root one and prove Scan Again reconciliation.
    final scanAgainPreviousJob = (await client.sources.getLibraryRoot(
      rootOneId,
    )).lastScan!.jobRunId;
    File('$rootOne/added.bin').writeAsBytesSync(<int>[1]);
    File('$rootOne/removed.bin').deleteSync();
    Directory('$rootOne/Moved').createSync();
    File('$rootOne/moved.bin').renameSync('$rootOne/Moved/moved.bin');

    await _waitForRootDetailReady(
      container,
      rootOneId,
      message: 'root one detail state never became ready',
    );
    final secondScanJobId = (await container
        .read(sourcesRootDetailControllerProvider(rootOneId).notifier)
        .startScan(rootOneId))!;
    final completedSecondJob = await _waitForRootLastScan(
      client,
      rootOneId,
      status: LibraryRootLastScanStatus.complete,
      previousJobId: scanAgainPreviousJob,
    );
    expect(completedSecondJob, secondScanJobId.value);
    expect(secondScanJobId.value, isNot(firstScanJobId));

    final afterRescan = await _rootChildren(client, rootOneId);
    expect(_entryNames(afterRescan), contains('added.bin'));
    expect(_entryNames(afterRescan), isNot(contains('removed.bin')));
    final movedDirectory = _entryById(afterRescan, 'Moved');
    expect(movedDirectory.kind, SourceEntryKind.directory);
    final movedChildren = await client.sources.listSourceEntryChildren(
      libraryRootId: rootOneId,
      parentSourceEntryId: movedDirectory.sourceEntryId,
      pageSize: 100,
    );
    final movedEntry = movedChildren.items.single;
    expect(movedEntry.displayName, 'moved.bin');
    // Trustworthy native move evidence preserves the entry identity; the
    // macOS provider derives Unix device/inode facts that make this provable.
    expect(movedEntry.sourceEntryId, movedId);

    // Step 3: add root two and prove Scan All independence.
    nextSelection = rootTwo;
    await _goToSources(tester, container);
    await _runAddLibraryFolderFlow(
      tester,
      container,
      choiceKey: const ValueKey<String>('add-folder-without-scan'),
    );
    await _waitForRootCount(client, 2);
    await _waitForRootListReady(
      container,
      message: 'sources root list never became ready',
    );
    await container
        .read(sourcesRootListControllerProvider.notifier)
        .startScanAll();
    final scanAllJobId = await _captureActiveJob(client);
    await _waitForJobLifecycle(
      client,
      scanAllJobId,
      JobLifecycleState.completed,
    );
    final scanAllDetail = _scanDetail(
      await client.jobs.getJob(JobRunId(scanAllJobId)),
    );
    expect(scanAllDetail.requestedRoots, hasLength(2));
    expect(scanAllDetail.scanRuns, hasLength(2));
    expect(
      scanAllDetail.scanRuns.every(
        (run) => run.status == JobScanStatus.complete,
      ),
      isTrue,
    );
    expect(scanAllDetail.progress.rootsAdmitted, 2);
    expect(scanAllDetail.progress.rootsTerminal, 2);

    final rootTwoId = await _rootIdByDisplayName(client, _displayName(rootTwo));
    final rootOneChildren = await _rootChildren(client, rootOneId);
    final rootTwoChildren = await _rootChildren(client, rootTwoId);
    expect(_entryNames(rootOneChildren), contains('keep.txt'));
    expect(
      _entryNames(rootTwoChildren),
      containsAll(<String>['only-two.bin', 'Second']),
    );
    expect(_entryNames(rootOneChildren), isNot(contains('only-two.bin')));
    expect(_entryNames(rootTwoChildren), isNot(contains('rom.bin')));

    // Step 4: cooperative cancellation through the real control path.
    _createCancellationTree('$rootOne/CancelBig');
    await _waitForRootDetailReady(
      container,
      rootOneId,
      message: 'root one detail state never became ready',
    );
    final cancelJobId = (await container
        .read(sourcesRootDetailControllerProvider(rootOneId).notifier)
        .startScan(rootOneId))!;
    await _waitUntilCanCancel(client, cancelJobId.value);
    // Cooperative cancellation through the same focused Jobs API the Jobs
    // controller invokes for the real control; the job detail controller is
    // not keep-alive and must not be read from a plain container.
    final cancelOutcome = await client.jobs.cancelJob(cancelJobId);
    expect(cancelOutcome, CancelJobResult.cancellationRequested);
    await _waitForJobLifecycle(
      client,
      cancelJobId.value,
      JobLifecycleState.cancelled,
    );

    final cancelledJob = await client.jobs.getJob(cancelJobId);
    expect(cancelledJob.job.cancellationRequested, isTrue);
    await _waitForRootLastScan(
      client,
      rootOneId,
      status: LibraryRootLastScanStatus.cancelled,
    );
    // Committed positive observations survive cancellation; cancellation
    // grants no absence authority.
    final afterCancel = await _rootChildren(client, rootOneId);
    expect(
      _entryNames(afterCancel),
      containsAll(<String>['keep.txt', 'rom.bin']),
    );
    Directory('$rootOne/CancelBig').deleteSync(recursive: true);

    // Step 5: root-removal safety and historical Jobs intelligibility.
    final removeNotifier = container.read(
      sourcesRootDetailControllerProvider(rootTwoId).notifier,
    );
    await _waitForRootDetailReady(
      container,
      rootTwoId,
      message: 'root two detail state never became ready',
    );
    await removeNotifier.remove(rootTwoId);
    await _waitForRootCount(client, 1);
    final remaining = await client.sources.listLibraryRoots(
      offset: 0,
      pageSize: 100,
    );
    expect(remaining.items.single.id, rootOneId);
    for (final name in <String>['only-two.bin', 'Second']) {
      expect(
        File('$rootTwo/$name').existsSync() ||
            Directory('$rootTwo/$name').existsSync(),
        isTrue,
        reason: 'user files must be untouched by root removal',
      );
    }

    final historical = await client.jobs.getJob(JobRunId(scanAllJobId));
    final historicalDetail = _scanDetail(historical);
    expect(historicalDetail.requestedRoots, hasLength(2));
    expect(
      historicalDetail.requestedRoots.map((root) => root.displayName),
      contains(_displayName(rootTwo)),
    );
    expect(historicalDetail.scanRuns, hasLength(2));
    expect(
      historicalDetail.scanRuns.every(
        (run) => run.status == JobScanStatus.complete,
      ),
      isTrue,
    );
    await client.jobs.getJob(JobRunId(firstScanJobId));
    await client.jobs.getJob(secondScanJobId);
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

/// Pumps the real production bootstrap with the test-owned data directory and
/// the narrow folder-picker seam.
Future<ProviderContainer> _pumpRealApp(
  WidgetTester tester,
  String dataDirectory, {
  required Future<LocalFilesystemRootSelection?> Function() picker,
}) async {
  await tester.pumpWidget(
    ArgusBootstrap(
      clientGatewayFactory: () =>
          FrbArgusClientGateway(dataDirectoryOverride: dataDirectory),
      libraryFolderPicker: picker,
    ),
  );
  return ProviderScope.containerOf(
    tester.element(find.byType(ArgusApp)),
    listen: false,
  );
}

/// Runs the real Add Library Folder flow with the injected selection and
/// waits for the chosen confirmation action to land on the root detail page.
Future<void> _runAddLibraryFolderFlow(
  WidgetTester tester,
  ProviderContainer container, {
  required Key choiceKey,
}) async {
  await tester.tap(
    find
        .byKey(const ValueKey<String>('sources-add-library-folder'))
        .hitTestable(),
  );
  await _waitForKey(
    tester,
    container,
    choiceKey,
    message: 'add folder confirmation did not appear',
    timeout: const Duration(seconds: 120),
  );
  await tester.tap(find.byKey(choiceKey).hitTestable());
  await _waitForKey(
    tester,
    container,
    const ValueKey<String>('sources-remove-library-folder'),
    message: 'root detail did not appear after the add flow',
    timeout: const Duration(seconds: 120),
  );
}

Future<String> _captureActiveJob(ArgusClient client) async {
  final deadline = DateTime.now().add(const Duration(seconds: 120));
  while (true) {
    final active = await client.jobs.listActiveJobs();
    if (active.items.isNotEmpty) return active.items.first.jobRunId.value;
    // A very fast scan may already be terminal by the time the poll starts;
    // the most recent terminal job is then the admission under test.
    final recent = await client.jobs.listRecentTerminalJobs(
      offset: 0,
      pageSize: 5,
    );
    if (recent.items.isNotEmpty) return recent.items.first.jobRunId.value;
    if (DateTime.now().isAfter(deadline)) {
      fail('no library-scan job appeared');
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
        'scan reached ${detail.job.lifecycleState} before cancellation; '
        'enlarge the cancellation fixture',
      );
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('durable job never exposed canCancel within 180s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> _waitForJobLifecycle(
  ArgusClient client,
  String jobRunId,
  JobLifecycleState expected,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 180));
  while (true) {
    final detail = await client.jobs.getJob(JobRunId(jobRunId));
    if (detail.job.lifecycleState == expected) return;
    if (detail.job.lifecycleState.isTerminal) {
      fail(
        'job $jobRunId reached ${detail.job.lifecycleState} '
        'instead of $expected',
      );
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('job $jobRunId did not reach $expected within 180s');
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
  final deadline = DateTime.now().add(const Duration(seconds: 180));
  while (true) {
    final root = await client.sources.getLibraryRoot(rootId);
    final lastScan = root.lastScan;
    if (lastScan != null && lastScan.jobRunId != previousJobId) {
      if (lastScan.status == status) return lastScan.jobRunId;
      fail(
        'root $rootId reached last-scan ${lastScan.status} '
        'instead of $status',
      );
    }
    if (DateTime.now().isAfter(deadline)) {
      await _dumpJobDiagnostics(client);
      fail('root $rootId last-scan never reached $status');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> _waitForRootDetailReady(
  ProviderContainer container,
  LibraryRootId rootId, {
  required String message,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final state = container.read(sourcesRootDetailControllerProvider(rootId));
    if (state.value is SourcesRootDetailStateReady) return;
    if (DateTime.now().isAfter(deadline)) {
      fail('$message (state: $state)');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> _waitForRootListReady(
  ProviderContainer container, {
  required String message,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final state = container.read(sourcesRootListControllerProvider);
    if (state.value is SourcesRootListStateReady) return;
    if (DateTime.now().isAfter(deadline)) {
      fail('$message (state: $state)');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<LibraryRootId> _onlyRootId(ArgusClient client) async {
  final page = await client.sources.listLibraryRoots(offset: 0, pageSize: 100);
  expect(page.totalCount, 1);
  return page.items.single.id;
}

Future<LibraryRootId> _rootIdByDisplayName(
  ArgusClient client,
  String displayName,
) async {
  final page = await client.sources.listLibraryRoots(offset: 0, pageSize: 100);
  return page.items.firstWhere((root) => root.displayName == displayName).id;
}

Future<void> _waitForRootCount(ArgusClient client, int expected) async {
  final deadline = DateTime.now().add(const Duration(seconds: 120));
  while (true) {
    final page = await client.sources.listLibraryRoots(
      offset: 0,
      pageSize: 100,
    );
    if (page.totalCount == expected) return;
    if (DateTime.now().isAfter(deadline)) {
      fail('root count never reached $expected');
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

LibraryScanJobDetail _scanDetail(JobDetail job) =>
    switch (job.operationDetail) {
      OperationDetailLibraryScan(:final detail) => detail,
    };

SourceEntry _entryById(List<SourceEntry> entries, String name) =>
    entries.firstWhere((entry) => entry.displayName == name);

List<String> _entryNames(List<SourceEntry> entries) => [
  for (final entry in entries) entry.displayName,
];

void _expectNames(List<SourceEntry> entries, Matcher namesMatcher) {
  expect(_entryNames(entries), namesMatcher);
}

String _displayName(String path) {
  final normalized = path.endsWith('/') || path.endsWith('\\')
      ? path.substring(0, path.length - 1)
      : path;
  final separator = Platform.isWindows ? '\\' : '/';
  return normalized.split(separator).last;
}

/// Creates a bounded, test-owned tree large enough that a scan observably
/// remains Running long enough for cooperative cancellation evidence.
void _createCancellationTree(String root) {
  Directory(root).createSync(recursive: true);
  for (var directoryIndex = 0; directoryIndex < 300; directoryIndex++) {
    final directory = Directory('$root/d$directoryIndex');
    directory.createSync();
    for (var fileIndex = 0; fileIndex < 50; fileIndex++) {
      File(
        '${directory.path}/f$fileIndex.bin',
      ).writeAsBytesSync(<int>[fileIndex]);
    }
  }
}

Future<void> _tapDestination(WidgetTester tester, String label) async {
  for (final containerType in <Type>[NavigationBar, NavigationRail]) {
    final candidate = find
        .descendant(of: find.byType(containerType), matching: find.text(label))
        .hitTestable();
    if (candidate.evaluate().isNotEmpty) {
      await tester.tap(candidate.first);
      await tester.pump();
      return;
    }
  }
  if (find.text(label).evaluate().isNotEmpty) {
    await tester.tap(find.text(label).first);
    await tester.pump();
  }
}

Future<void> _goToSources(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (true) {
    if (find
        .byKey(const ValueKey<String>('sources-add-library-folder'))
        .hitTestable()
        .evaluate()
        .isNotEmpty) {
      return;
    }
    await _tapDestination(tester, 'Sources');
    await tester.pump(const Duration(milliseconds: 200));
    if (DateTime.now().isAfter(deadline)) {
      fail('could not navigate to the Sources page');
    }
  }
}

Future<void> _waitForShell(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await _pumpUntil(
    tester,
    container: container,
    condition: () =>
        find.text('Sources').evaluate().isNotEmpty ||
        find.text('Settings').evaluate().isNotEmpty,
    message: 'normal application shell did not appear',
    timeout: const Duration(seconds: 90),
  );
}

Future<void> _waitForKey(
  WidgetTester tester,
  ProviderContainer container,
  Key key, {
  required String message,
  Duration timeout = const Duration(seconds: 60),
}) async {
  await _pumpUntil(
    tester,
    container: container,
    condition: () => find.byKey(key).hitTestable().evaluate().isNotEmpty,
    message: message,
    timeout: timeout,
  );
}

Future<void> _waitForText(
  WidgetTester tester,
  ProviderContainer container,
  String text,
) async {
  await _pumpUntil(
    tester,
    container: container,
    condition: () => find.text(text).hitTestable().evaluate().isNotEmpty,
    message: 'text "$text" did not appear',
  );
}

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

/// Prints bounded durable job facts (never raw paths) when a scan wait times
/// out, so application/transport/environment failures stay distinguishable.
Future<void> _dumpJobDiagnostics(ArgusClient client) async {
  final page = await client.jobs.listActiveJobs();
  debugPrint(
    'Active jobs at timeout: '
    '${[for (final item in page.items) '${item.lifecycleState}/${item.phase}']}',
  );
  for (final item in page.items) {
    final detail = await client.jobs.getJob(item.jobRunId);
    debugPrint(
      'Job ${item.jobRunId.value} state=${detail.job.lifecycleState} '
      'canCancel=${detail.job.controls.canCancel}',
    );
  }
}

/// Prints bounded diagnostics without raw user filesystem paths.
void _dumpVisibleState(WidgetTester tester, ProviderContainer container) {
  final keys = find
      .byWidgetPredicate((widget) => widget.key is ValueKey<String>)
      .evaluate()
      .map((element) => (element.widget.key as ValueKey<String>).value)
      .toList();
  debugPrint('Visible ValueKey widgets at timeout: $keys');
  debugPrint(
    'Startup state at timeout: '
    '${container.read(startupControllerProvider)}',
  );
}

/// Shuts the native runtime down, disposes the root client, then detaches.
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
