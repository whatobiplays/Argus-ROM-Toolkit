import 'dart:io';

import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/bootstrap/app_bootstrap.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/app/platform/platform_host.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/jobs/jobs.dart';
import 'package:argus/features/sources/sources.dart';
import 'package:argus/features/startup/application/app_readiness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Repository-owned real Android P02-004 foreground-execution milestone.
///
/// The shell harness controls Activity backgrounding, screen-off, notification
/// actions, platform timeout settings, and process death. This test keeps all
/// durable assertions on the existing typed client APIs and never treats the
/// notification or service state as Jobs truth.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const mode = String.fromEnvironment('ARGUS_PHASE_002_FOREGROUND_MODE');
  const evidencePath = String.fromEnvironment(
    'ARGUS_PHASE_002_FOREGROUND_EVIDENCE_PATH',
  );
  const continuePath = String.fromEnvironment(
    'ARGUS_PHASE_002_FOREGROUND_CONTINUE_PATH',
  );
  const fixtureName = 'ArgusP02004Fixture';
  const supportedModes = <String>{
    'continuity',
    'notificationDenied',
    'notificationCancel',
    'timeout',
    'recoveryStart',
    'recoveryCheck',
  };
  if (!supportedModes.contains(mode)) {
    throw StateError('Unsupported P02-004 foreground mode: $mode');
  }
  if (evidencePath.isEmpty || !evidencePath.startsWith('/')) {
    throw StateError('P02-004 evidence path must be absolute');
  }

  testWidgets('Android P02-004 foreground execution milestone', (tester) async {
    await tester.pumpWidget(const ArgusBootstrap());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ArgusApp)),
      listen: false,
    );
    if (mode == 'notificationDenied' || mode == 'notificationCancel') {
      await _requestNotificationPermissionIfRequired(
        container,
        tester,
        '$evidencePath.notification-prompt',
      );
    }
    await _pumpUntil(
      tester,
      find.byKey(const ValueKey<String>('compact-navigation-bar')),
      message: 'Android application shell did not become ready',
    );
    final client = container.read(argusClientProvider);
    final sources = container.read(sourcesApiProvider);
    final jobs = container.read(jobsApiProvider);
    final generation = container.read(readyRuntimeInstanceIdProvider);
    expect(generation, isNotNull);

    switch (mode) {
      case 'continuity':
        await _runContinuity(
          client,
          sources,
          jobs,
          generation!,
          evidencePath,
          continuePath,
          fixtureName,
        );
      case 'notificationDenied':
        await _runNotificationDenied(sources, jobs, evidencePath, fixtureName);
      case 'notificationCancel':
        await _runNotificationCancel(sources, jobs, evidencePath, fixtureName);
      case 'timeout':
        await _runTimeout(sources, jobs, evidencePath, fixtureName);
      case 'recoveryStart':
        await _runRecoveryStart(
          sources,
          jobs,
          evidencePath,
          continuePath,
          fixtureName,
        );
      case 'recoveryCheck':
        await _runRecoveryCheck(jobs, evidencePath);
    }
  });
}

/// Starts the real Android notification permission request when the platform
/// readiness gate requires it and leaves the harness a marker while the
/// system dialog is open. The shell harness answers with the mode-appropriate
/// Android action, keeping the evidence tied to the platform permission
/// lifecycle.
Future<void> _requestNotificationPermissionIfRequired(
  ProviderContainer container,
  WidgetTester tester,
  String promptMarkerPath,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    final readiness = container.read(platformReadinessControllerProvider);
    if (readiness is PlatformReadinessRequiresNotificationPermission) {
      _writeEvidence(promptMarkerPath, 'prompt');
      await container
          .read(platformReadinessControllerProvider.notifier)
          .requestNotificationPermission();
      return;
    }
    if (readiness is PlatformReadinessReady) return;
    await tester.pump(const Duration(milliseconds: 200));
  }
  fail('Timed out waiting for the notification permission readiness step');
}

Future<void> _runContinuity(
  ArgusClient client,
  SourcesApi sources,
  JobsApi jobs,
  RuntimeInstanceId generation,
  String evidencePath,
  String continuePath,
  String fixtureName,
) async {
  final jobRunId = await _startFixtureScan(sources, fixtureName);
  final before = await _waitForActiveJob(jobs, jobRunId);
  final beforeEntriesCommitted = _entriesCommitted(before);
  _writeEvidence(
    evidencePath,
    '$jobRunId|${beforeEntriesCommitted ?? 'unknown'}',
  );
  await _waitForFile(continuePath);

  final afterGeneration = await _readGeneration(client);
  expect(afterGeneration, generation);
  final after = await jobs.getJob(jobRunId);
  expect(after.job.jobRunId, jobRunId);
  final activeRows = await jobs.listActiveJobs();
  final matching = activeRows.items
      .where((item) => item.jobRunId == jobRunId)
      .toList(growable: false);
  if (after.job.lifecycleState.isTerminal) {
    expect(matching, isEmpty);
    return;
  }

  expect(matching.length, 1);
  final afterEntriesCommitted = _entriesCommitted(after);
  expect(
    afterEntriesCommitted,
    isNotNull,
    reason:
        'A still-active scan must expose authoritative committed progress '
        'after the lifecycle transitions',
  );
  if (beforeEntriesCommitted == null) {
    expect(
      afterEntriesCommitted,
      greaterThan(0),
      reason:
          'Continuity must prove useful committed work when the pre-background '
          'observation was unavailable',
    );
  } else {
    expect(
      afterEntriesCommitted,
      greaterThan(beforeEntriesCommitted),
      reason:
          'Continuity must prove committed progress advanced after the '
          'background/recreate/screen-off sequence',
    );
  }
  await _waitForTerminal(jobs, jobRunId);
}

Future<void> _runNotificationDenied(
  SourcesApi sources,
  JobsApi jobs,
  String evidencePath,
  String fixtureName,
) async {
  final jobRunId = await _startFixtureScan(sources, fixtureName);
  _writeEvidence(evidencePath, jobRunId.value);
  final terminal = await _waitForTerminal(jobs, jobRunId);
  expect(
    terminal.job.lifecycleState,
    isNot(anyOf(JobLifecycleState.abandoned, JobLifecycleState.interrupted)),
  );
}

Future<void> _runNotificationCancel(
  SourcesApi sources,
  JobsApi jobs,
  String evidencePath,
  String fixtureName,
) async {
  final jobRunId = await _startFixtureScan(sources, fixtureName);
  await _waitForActiveJob(jobs, jobRunId);
  _writeEvidence(evidencePath, jobRunId.value);
  final cancelMarker = '$evidencePath.cancel-invoked';
  await _waitForFile(cancelMarker);
  final terminal = await _waitForTerminal(jobs, jobRunId);
  expect(terminal.job.lifecycleState, JobLifecycleState.cancelled);
  expect(terminal.job.cancellationRequested, isTrue);
}

Future<void> _runTimeout(
  SourcesApi sources,
  JobsApi jobs,
  String evidencePath,
  String fixtureName,
) async {
  final jobRunId = await _startFixtureScan(sources, fixtureName);
  final active = await _waitForActiveJob(jobs, jobRunId);
  _writeEvidence(
    evidencePath,
    '$jobRunId|initial=${_entriesCommitted(active) ?? 'unknown'}',
  );
  final terminal = await _waitForTerminal(jobs, jobRunId);
  expect(
    terminal.job.lifecycleState,
    anyOf(JobLifecycleState.failed, JobLifecycleState.completedWithIssues),
  );
  expect(
    terminal.job.lifecycleState,
    isNot(anyOf(JobLifecycleState.abandoned, JobLifecycleState.interrupted)),
  );
  final terminalEntriesCommitted = _entriesCommitted(terminal);
  expect(
    terminalEntriesCommitted,
    isNotNull,
    reason:
        'Timeout classification must use authoritative terminal operation '
        'facts, not only the first active snapshot',
  );
  if (terminalEntriesCommitted! > 0) {
    expect(terminal.job.lifecycleState, JobLifecycleState.completedWithIssues);
  }
}

Future<void> _runRecoveryStart(
  SourcesApi sources,
  JobsApi jobs,
  String evidencePath,
  String continuePath,
  String fixtureName,
) async {
  final jobRunId = await _startFixtureScan(sources, fixtureName);
  await _waitForActiveJob(jobs, jobRunId);
  _writeEvidence(evidencePath, jobRunId.value);
  // Keep the application process alive after the durable active-job proof. The
  // shell harness must inspect the service's live foreground state immediately
  // before it deliberately force-stops the package.
  await _waitForFile(continuePath);
}

Future<void> _runRecoveryCheck(JobsApi jobs, String evidencePath) async {
  final jobRunId = JobRunId(File(evidencePath).readAsStringSync().trim());
  expect(jobRunId.isValid, isTrue);
  final active = await jobs.listActiveJobs();
  expect(active.items.where((item) => item.jobRunId == jobRunId), isEmpty);
  final terminal = await _waitForTerminal(jobs, jobRunId);
  expect(terminal.job.lifecycleState, JobLifecycleState.abandoned);
}

Future<JobRunId> _startFixtureScan(
  SourcesApi sources,
  String fixtureName,
) async {
  final selection = await _fixtureSelection(sources, fixtureName);
  final result = await sources.addLocalLibraryRootAndScan(selection);
  return switch (result) {
    AddLocalLibraryRootAndScanResultAddedAndScanAdmitted(:final handle) =>
      handle.jobRunId,
    AddLocalLibraryRootAndScanResultAddedButScanNotAdmitted(:final issue) =>
      switch (issue) {
        LibraryScanChildAdmissionIssueAlreadyScanning(:final activeJobRunId) =>
          activeJobRunId,
        LibraryScanChildAdmissionIssueAdmissionFailure(:final error) => fail(
          'Add & Scan child admission failed: ${error.code}',
        ),
      },
    AddLocalLibraryRootAndScanResultAlreadyConfigured(
      :final existingLibraryRootId,
    ) =>
      await _startExistingRootScan(sources, existingLibraryRootId),
    AddLocalLibraryRootAndScanResultOverlapsExisting() => fail(
      'P02-004 fixture overlaps an existing root',
    ),
  };
}

Future<JobRunId> _startExistingRootScan(
  SourcesApi sources,
  LibraryRootId libraryRootId,
) async {
  final result = await sources.startLibraryScan(libraryRootId);
  return switch (result) {
    StartLibraryScanResultAdmitted(:final handle) => handle.jobRunId,
    StartLibraryScanResultAlreadyScanning(:final activeJobRunId) =>
      activeJobRunId,
  };
}

Future<LocalFilesystemRootSelection> _fixtureSelection(
  SourcesApi sources,
  String fixtureName,
) async {
  for (final root in await sources.listLocalFilesystemBrowseRoots()) {
    final page = await sources.listLocalFilesystemBrowseDirectories(
      location: root.location,
      pageSize: 100,
    );
    for (final directory in page.directories) {
      if (directory.displayName == fixtureName) {
        return LocalFilesystemRootSelection.providerSelection(
          directory.location.value,
        );
      }
    }
  }
  fail('No mounted Android fixture named $fixtureName');
}

Future<JobDetail> _waitForActiveJob(JobsApi jobs, JobRunId jobRunId) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    final detail = await jobs.getJob(jobRunId);
    if (!detail.job.lifecycleState.isTerminal) return detail;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('Timed out waiting for active JobRun $jobRunId');
}

Future<JobDetail> _waitForTerminal(JobsApi jobs, JobRunId jobRunId) async {
  // The native milestone uses a bounded FUSE-backed fixture so host-driven
  // lifecycle actions have time to run before terminalization.
  final deadline = DateTime.now().add(const Duration(minutes: 10));
  while (DateTime.now().isBefore(deadline)) {
    final detail = await jobs.getJob(jobRunId);
    if (detail.job.lifecycleState.isTerminal) return detail;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('Timed out waiting for terminal JobRun $jobRunId');
}

Future<RuntimeInstanceId> _readGeneration(ArgusClient client) async {
  final state = await client.runtime.getRuntimeState();
  return switch (state) {
    RuntimeStateReady(:final runtimeInstanceId) => runtimeInstanceId,
    _ => fail('Runtime left Ready while foreground host was active'),
  };
}

int? _entriesCommitted(JobDetail detail) => switch (detail.operationDetail) {
  OperationDetailLibraryScan(:final detail) => detail.progress.entriesCommitted,
};

void _writeEvidence(String path, String value) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(value);
}

Future<void> _waitForFile(String path) async {
  if (path.isEmpty) return;
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  while (DateTime.now().isBefore(deadline)) {
    if (File(path).existsSync()) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('Timed out waiting for harness marker $path');
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  required String message,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail(message);
}
