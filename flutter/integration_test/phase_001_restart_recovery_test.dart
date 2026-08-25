import 'dart:io';

import 'package:argus/app/bootstrap/app_bootstrap.dart';
import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/core/bridge/bridge.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/sources/application/root_detail_controller.dart';
import 'package:argus/features/sources/presentation/selected_library_folder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'native_onboarding_test_support.dart';

/// Test-owned environment inputs for the Phase 001 restart proof.
const String _restartModeEnvironment = 'ARGUS_PHASE_001_RESTART_MODE';
const String _dataDirectoryEnvironment = 'ARGUS_PHASE_001_DATA_DIR';
const String _rootOneEnvironment = 'ARGUS_PHASE_001_ROOT_ONE';

/// Sentinel file written only after the seed process proves durable Running.
/// Its presence distinguishes the expected intentional interruption from an
/// accidental seed-test failure.
const String _sentinelFileName = 'phase-001-restart-seed.sentinel';

/// Real two-native-process Phase 001 restart-recovery proof.
///
/// The seed process launches the real production bootstrap against an
/// isolated test-owned data directory, adds one library root, starts a real
/// scan over a bounded large tree through the same root-detail controller the
/// Scan Again button invokes, waits until the durable job is Running and at
/// least one positive observation is committed, writes a test-owned sentinel,
/// and then terminates the process without `generalShutdown`, `CancelJob`,
/// normal scan completion, or any other terminalization.
///
/// The verify process launches a distinct native process against the same
/// data directory and asserts the Slice 006 recovery contract exactly: the
/// stale Running child with no accepted durable cancellation intent becomes
/// `Abandoned`; active ownership was cleared; committed positive observations
/// survive; incomplete work gained no destructive absence authority; no
/// new admission occurred during startup recovery; and no scan automatically
/// resumes.
///
/// Provider-I/O evidence: the harness makes the configured library root path
/// unavailable (moves it away) after the seed terminates and before this
/// process launches. Startup recovery must still reach `Ready` and reconcile
/// the stale job to `Abandoned` without resolving or enumerating the root;
/// committed source observations remain readable from the test-owned SQLite
/// application data and are asserted here without touching the filesystem.
/// The lower-level Slice 006 Rust recovery tests remain the complementary
/// deterministic evidence for the persistence-only reconciler.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final mode = Platform.environment[_restartModeEnvironment];
  final dataDirectory = Platform.environment[_dataDirectoryEnvironment];
  final rootOne = Platform.environment[_rootOneEnvironment];
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
  if (mode == 'seed' &&
      (rootOne == null ||
          rootOne.isEmpty ||
          !Directory(rootOne).existsSync())) {
    throw StateError(
      '$_rootOneEnvironment must be an existing absolute directory path',
    );
  }
  final directory = Directory(dataDirectory);
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }

  switch (mode) {
    case 'seed':
      testWidgets('seed process reaches durable Running then terminates '
          'without terminalizing the scan', (tester) async {
        await _runSeedPhase(tester, dataDirectory, rootOne!);
      });
    case 'verify':
      testWidgets('verify process proves Abandoned recovery with no '
          'auto-resume', (tester) async {
        await _runVerifyPhase(tester, dataDirectory);
      });
  }
}

Future<void> _runSeedPhase(
  WidgetTester tester,
  String dataDirectory,
  String rootOne,
) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = await _pumpRealApp(tester, dataDirectory, rootOne);
  final client = container.read(argusClientProvider);
  await completeNativeLibraryOnboarding(tester, temporaryRootPath: rootOne);
  await _waitForShell(tester, container);
  await _goToSources(tester, container);

  final onboardingJobs = await client.jobs.listRecentTerminalJobs(
    offset: 0,
    pageSize: 100,
  );

  // Configure root one without scanning, then start one scan over a tree
  // large enough that it observably remains Running.
  await _runAddLibraryFolderFlow(
    tester,
    container,
    choiceKey: const ValueKey<String>('add-folder-without-scan'),
  );
  _createLargeTree('$rootOne/SeedBig');
  final page = await client.sources.listLibraryRoots(offset: 0, pageSize: 100);
  final rootOneId = page.items.single.id;
  await _waitForRootDetailReady(
    container,
    rootOneId,
    message: 'root one detail state never became ready',
  );
  final jobRunId = (await container
      .read(sourcesRootDetailControllerProvider(rootOneId).notifier)
      .startScan(rootOneId))!;
  await _waitUntilRunning(client, jobRunId.value);
  final committed = await _waitForFirstCommittedChildren(client);
  File('$dataDirectory/$_sentinelFileName').writeAsStringSync(
    'job_run_id=${jobRunId.value}\n'
    'committed=${committed.join(',')}\n'
    'baseline_job_run_ids=${onboardingJobs.items.map((job) => job.jobRunId.value).join(',')}\n',
  );
  // Intentional interruption: terminate the native process now without
  // generalShutdown, CancelJob, scan completion, or any other
  // terminalization. The harness treats a missing sentinel as an accidental
  // seed failure.
  exit(0);
}

Future<void> _runVerifyPhase(WidgetTester tester, String dataDirectory) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final sentinel = File('$dataDirectory/$_sentinelFileName');
  if (!sentinel.existsSync()) {
    fail('restart seed sentinel is missing; the seed never proved Running');
  }
  final sentinelLines = sentinel.readAsStringSync().split('\n');
  String jobRunId = '';
  final committed = <String>[];
  final baselineJobRunIds = <String>[];
  for (final line in sentinelLines) {
    if (line.startsWith('job_run_id=')) {
      jobRunId = line.substring('job_run_id='.length);
    } else if (line.startsWith('committed=')) {
      committed.addAll(
        line
            .substring('committed='.length)
            .split(',')
            .where((name) => name.isNotEmpty),
      );
    } else if (line.startsWith('baseline_job_run_ids=')) {
      baselineJobRunIds.addAll(
        line
            .substring('baseline_job_run_ids='.length)
            .split(',')
            .where((id) => id.isNotEmpty),
      );
    }
  }
  if (jobRunId.isEmpty || committed.isEmpty || baselineJobRunIds.isEmpty) {
    fail('restart seed sentinel is malformed');
  }

  final container = await _pumpRealApp(tester, dataDirectory, '');
  Object? bodyError;
  StackTrace? bodyStack;
  try {
    final client = container.read(argusClientProvider);
    await _waitForShell(tester, container);

    // No scan may automatically resume: active ownership is cleared and no
    // new admission exists.
    final active = await client.jobs.listActiveJobs();
    expect(active.items, isEmpty);

    // The interrupted execution maps to the documented durable recovery
    // state: stale Running child + no accepted cancellation -> Abandoned.
    final recovered = await client.jobs.getJob(JobRunId(jobRunId));
    expect(recovered.job.lifecycleState, JobLifecycleState.abandoned);
    final scanRun = _scanDetail(recovered).scanRuns.single;
    expect(scanRun.status, JobScanStatus.abandoned);
    expect(recovered.job.terminalAtMs, isNotNull);

    // The root remains configured with the recovery summary; recovery does
    // not change root availability merely because execution stopped.
    final page = await client.sources.listLibraryRoots(
      offset: 0,
      pageSize: 100,
    );
    expect(page.totalCount, 1);
    final root = page.items.single;
    expect(root.lastScan, isNotNull);
    expect(root.lastScan!.status, LibraryRootLastScanStatus.abandoned);
    expect(root.lastScan!.jobRunId, jobRunId);
    // Recovery must not resolve the provider or flip persisted availability
    // merely because the filesystem root is currently absent.
    expect(root.availability, LibraryRootAvailability.available);

    // Committed positive observations survive the interruption, and the
    // incomplete scan gained no destructive absence authority.
    final children = await client.sources.listSourceEntryChildren(
      libraryRootId: root.id,
      pageSize: 200,
    );
    final names = [for (final entry in children.items) entry.displayName];
    for (final committedName in committed) {
      expect(names, contains(committedName));
    }

    // Recovery preserves the onboarding refresh history and adds no new job:
    // the only new terminal execution is the interrupted scan itself.
    final terminal = await client.jobs.listRecentTerminalJobs(
      offset: 0,
      pageSize: 10,
    );
    expect(
      terminal.items.map((item) => item.jobRunId.value),
      unorderedEquals(<String>{...baselineJobRunIds, jobRunId}),
    );
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

Future<ProviderContainer> _pumpRealApp(
  WidgetTester tester,
  String dataDirectory,
  String rootOne,
) async {
  await tester.pumpWidget(
    ArgusBootstrap(
      clientGatewayFactory: () =>
          FrbArgusClientGateway(dataDirectoryOverride: dataDirectory),
      libraryFolderPicker: (_, _) async => rootOne.isEmpty
          ? null
          : SelectedLibraryFolder(
              selection: LocalFilesystemRootSelection(rootOne),
              displayName: 'Selected root',
              safeLocationPresentation: rootOne,
            ),
    ),
  );
  return ProviderScope.containerOf(
    tester.element(find.byType(ArgusApp)),
    listen: false,
  );
}

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
  );
  await tester.tap(find.byKey(choiceKey).hitTestable());
  await _waitForKey(
    tester,
    container,
    const ValueKey<String>('sources-remove-library-folder'),
    message: 'root detail did not appear after the add flow',
  );
}

Future<void> _waitUntilRunning(ArgusClient client, String jobRunId) async {
  final deadline = DateTime.now().add(const Duration(seconds: 120));
  while (true) {
    final detail = await client.jobs.getJob(JobRunId(jobRunId));
    if (detail.job.lifecycleState == JobLifecycleState.running) {
      return;
    }
    if (detail.job.lifecycleState.isTerminal) {
      fail(
        'seed scan reached ${detail.job.lifecycleState} before Running; '
        'enlarge the seed tree',
      );
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('seed scan never became durably Running');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<List<String>> _waitForFirstCommittedChildren(ArgusClient client) async {
  final deadline = DateTime.now().add(const Duration(seconds: 120));
  while (true) {
    final page = await client.sources.listLibraryRoots(
      offset: 0,
      pageSize: 100,
    );
    if (page.items.isNotEmpty) {
      final children = await client.sources.listSourceEntryChildren(
        libraryRootId: page.items.single.id,
        pageSize: 200,
      );
      if (children.items.isNotEmpty) {
        return [for (final entry in children.items) entry.displayName];
      }
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('seed scan never committed a positive observation');
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

void _createLargeTree(String root) {
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

LibraryScanJobDetail _scanDetail(JobDetail job) =>
    switch (job.operationDetail) {
      OperationDetailLibraryScan(:final detail) => detail,
      _ => throw StateError('Expected a library_scan operation detail'),
    };

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
      fail('$message (timed out after ${timeout.inSeconds} seconds)');
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
}

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
