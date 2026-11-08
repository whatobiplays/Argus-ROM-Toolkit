import 'package:argus/core/client/client.dart';
import 'package:argus/features/jobs/jobs.dart';
import 'package:argus/features/jobs/presentation/jobs_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'jobs_test_fakes.dart';

TransportFailure transportFailure() =>
    const TransportFailure('fake transport failure');

void main() {
  test(
    'scan failure copy allowlists durable reasons and hides unknown input',
    () {
      expect(
        JobsMessages.scanFailureReasonLabel('source_access_failed'),
        'The scan could not read this folder\'s contents.',
      );
      expect(
        JobsMessages.scanFailureReasonLabel('source_unavailable'),
        'This folder was unavailable during the scan.',
      );
      expect(
        JobsMessages.scanFailureReasonLabel('admission_registration_failed'),
        'The scan could not be started for this folder.',
      );
      expect(
        JobsMessages.scanFailureReasonLabel('execution_host_timeout'),
        'The scan stopped because its execution host timed out.',
      );
      expect(
        JobsMessages.scanFailureReasonLabel('execution_host_lost'),
        'The scan stopped because its execution host was lost.',
      );
      expect(
        JobsMessages.scanFailureReasonLabel('finalization_authority_changed'),
        'The scan result could not be finalized because its source changed.',
      );
      expect(
        JobsMessages.scanFailureReasonLabel('incomplete_scope'),
        'Some contents of this folder could not be fully scanned.',
      );
      expect(
        JobsMessages.scanFailureReasonLabel('internal'),
        JobsMessages.scanFailureInternal,
      );
      expect(
        JobsMessages.scanFailureReasonLabel('internal'),
        isNot('internal'),
      );
      expect(
        JobsMessages.scanFailureReasonLabel(
          '/data/user/0/app/private.key SELECT * FROM credentials',
        ),
        JobsMessages.scanFailureUnknown,
      );
      expect(
        JobsMessages.scanFailureReasonLabel(null),
        JobsMessages.scanFailureUnknown,
      );
    },
  );

  test('Complete refresh fixture preserves one supported outcome per root', () {
    final jobId = JobRunId('d' * 32);
    const rootA = LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    const rootB = LibraryRootId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
    final scan = _refreshScan('11111111111111111111111111111111', jobId, rootA);
    const exclusion = LibraryScanAdmissionExclusion(
      libraryRootId: rootB,
      reason: 'already_scanning',
    );
    final detail = _completeRefreshAttempt(
      jobRunId: jobId,
      requestedRootIds: const [rootB, rootA],
      scanRuns: [scan],
      exclusions: const [exclusion],
    );
    final refresh =
        (detail.operationDetail as OperationDetailLibraryRefresh).detail;
    expect(
      refresh.rootOutcomeCoverage,
      LibraryRefreshRootOutcomeCoverage.complete,
    );
    expect(refresh.requestedRootIds, const [rootB, rootA]);
    expect(refresh.scanRuns, [scan]);
    expect(refresh.exclusions, const [exclusion]);
  });

  test('Complete fixture rejects incomplete or contradictory outcomes', () {
    final jobId = JobRunId('d' * 32);
    final otherJobId = JobRunId('e' * 32);
    const rootA = LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    const rootB = LibraryRootId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
    final scanA = _refreshScan(
      '11111111111111111111111111111111',
      jobId,
      rootA,
    );
    final scanB = _refreshScan(
      '22222222222222222222222222222222',
      jobId,
      rootB,
    );
    final sameRoot = _refreshScan(
      '33333333333333333333333333333333',
      jobId,
      rootA,
    );
    final duplicateScanId = _refreshScan(scanA.scanRunId.value, jobId, rootB);
    final foreignJob = _refreshScan(
      '44444444444444444444444444444444',
      otherJobId,
      rootA,
    );
    const excludedA = LibraryScanAdmissionExclusion(
      libraryRootId: rootA,
      reason: 'already_scanning',
    );
    const excludedB = LibraryScanAdmissionExclusion(
      libraryRootId: rootB,
      reason: 'already_scanning',
    );

    JobDetail attempt(
      List<LibraryRootId> roots,
      List<ScanRunSummary> scans,
      List<LibraryScanAdmissionExclusion> exclusions,
    ) => _completeRefreshAttempt(
      jobRunId: jobId,
      requestedRootIds: roots,
      scanRuns: scans,
      exclusions: exclusions,
    );

    final invalid = <String, JobDetail Function()>{
      'missing root outcome': () => attempt([rootA, rootB], [scanA], []),
      'duplicate requested root': () => attempt([rootA, rootA], [scanA], []),
      'unrequested ScanRun': () => attempt([rootA], [scanA, scanB], []),
      'duplicate ScanRun root': () => attempt([rootA], [scanA, sameRoot], []),
      'ScanRun and exclusion collision': () =>
          attempt([rootA], [scanA], [excludedA]),
      'duplicate exclusion root': () =>
          attempt([rootA, rootB], [scanA], [excludedB, excludedB]),
      'unrequested exclusion': () => attempt([rootA], [scanA], [excludedB]),
      'duplicate ScanRun identity': () =>
          attempt([rootA, rootB], [scanA, duplicateScanId], []),
      'ScanRun from another job': () => attempt([rootA], [foreignJob], []),
    };
    for (final entry in invalid.entries) {
      expect(entry.value, throwsArgumentError, reason: entry.key);
    }
  });

  test('Library refresh detail fake defaults to a terminal lifecycle', () {
    expect(
      libraryRefreshJobDetail().job.lifecycleState,
      JobLifecycleState.completedWithIssues,
    );
  });

  ProviderContainer createContainer(JobsApi api) {
    final container = ProviderContainer(
      overrides: [
        jobsApiProvider.overrideWithValue(api),
        jobsRuntimeContextProvider.overrideWithValue(
          const JobsRuntimeContext.ready(
            runtimeInstanceId: RuntimeInstanceId(
              '1234567890abcdef1234567890abcdef',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'list controller loads active and recent and pages recent history',
    () async {
      final api = FakeJobsApi(
        activeJobs: [jobItem(id: 'a' * 32)],
        recentJobs: [
          for (var index = 0; index < 25; index++)
            jobItem(
              id: index.toRadixString(16).padLeft(32, '0'),
              state: JobLifecycleState.completed,
            ),
        ],
      );
      final container = createContainer(api);
      final provider = jobsListControllerProvider;
      await container.read(provider.notifier).refresh();
      final first = container.read(provider).requireValue as JobsListStateReady;
      expect(first.activeJobs, hasLength(1));
      expect(first.recentJobs, hasLength(20));
      expect(first.nextOffset, 20);

      await container.read(provider.notifier).loadMore();
      final second =
          container.read(provider).requireValue as JobsListStateReady;
      expect(second.recentJobs, hasLength(25));
      expect(second.nextOffset, isNull);
    },
  );

  test('detail controller reconciles after cancellation', () async {
    final runningId = JobRunId('a' * 32);
    final api = FakeJobsApi(
      details: {
        runningId: jobDetail(id: 'a' * 32, state: JobLifecycleState.running),
      },
    );
    final container = createContainer(api);
    final provider = jobDetailControllerProvider(runningId);
    await container.read(provider.notifier).refresh(runningId);
    final ready = container.read(provider).requireValue as JobDetailStateReady;
    expect(ready.detail.job.controls.canCancel, isTrue);

    api.details[runningId] = jobDetail(
      id: 'a' * 32,
      state: JobLifecycleState.cancelled,
      cancellationRequested: true,
    );
    await container.read(provider.notifier).cancel(runningId);
    final after = container.read(provider).requireValue as JobDetailStateReady;
    expect(after.detail.job.lifecycleState, JobLifecycleState.cancelled);
    expect(after.detail.job.controls.canCancel, isFalse);
    expect(api.cancelCalls, 1);
  });

  test('retry admitted navigates to the new execution identity', () async {
    final oldId = JobRunId('a' * 32);
    final newId = JobRunId('b' * 32);
    final api =
        FakeJobsApi(
            details: {
              oldId: jobDetail(
                id: 'a' * 32,
                state: JobLifecycleState.failed,
                canRetry: true,
              ),
            },
          )
          ..onRetry = (jobRunId) => RetryJobResult.admitted(
            OperationHandle(jobRunId: newId, operationType: 'library_scan'),
          );
    final container = createContainer(api);
    final provider = jobDetailControllerProvider(oldId);
    await container.read(provider.notifier).refresh(oldId);
    final navigated = <JobRunId>[];
    await container
        .read(provider.notifier)
        .retry(oldId, onAdmitted: navigated.add);
    expect(api.retryCalls, 1);
    expect(navigated, [newId]);
  });

  test(
    'AlreadyRetried resolves to the existing successor without dispatch',
    () async {
      final oldId = JobRunId('a' * 32);
      final successorId = JobRunId('c' * 32);
      final api = FakeJobsApi(
        details: {
          oldId: jobDetail(
            id: 'a' * 32,
            state: JobLifecycleState.failed,
            canRetry: true,
          ),
        },
      )..onRetry = (jobRunId) => RetryJobResult.alreadyRetried(successorId);
      final container = createContainer(api);
      final provider = jobDetailControllerProvider(oldId);
      await container.read(provider.notifier).refresh(oldId);
      final navigated = <JobRunId>[];
      await container
          .read(provider.notifier)
          .retry(oldId, onAdmitted: navigated.add);
      expect(api.retryCalls, 1);
      expect(navigated, [successorId]);
    },
  );

  test('NotAdmitted stays on the historical run with a typed reason', () async {
    final oldId = JobRunId('a' * 32);
    final api =
        FakeJobsApi(
            details: {
              oldId: jobDetail(
                id: 'a' * 32,
                state: JobLifecycleState.failed,
                canRetry: true,
              ),
            },
          )
          ..onRetry = (jobRunId) => RetryJobResult.notAdmitted(
            const RetryNotAdmittedReason.noEligibleTargets([]),
          );
    final container = createContainer(api);
    final provider = jobDetailControllerProvider(oldId);
    await container.read(provider.notifier).refresh(oldId);
    final navigated = <JobRunId>[];
    await container
        .read(provider.notifier)
        .retry(oldId, onAdmitted: navigated.add);
    final state = container.read(provider).requireValue as JobDetailStateReady;
    expect(navigated, isEmpty);
    expect(
      state.retryNotAdmittedReason,
      isA<RetryNotAdmittedReasonNoEligibleTargets>(),
    );
  });

  test('ambiguous retry never dispatches twice and navigates only after the '
      'authoritative successor appears', () async {
    final oldId = JobRunId('a' * 32);
    final successorId = JobRunId('b' * 32);
    final api = FakeJobsApi(
      details: {
        oldId: jobDetail(
          id: 'a' * 32,
          state: JobLifecycleState.failed,
          canRetry: true,
        ),
      },
    )..onRetry = (jobRunId) => throw transportFailure();
    final container = createContainer(api);
    final provider = jobDetailControllerProvider(oldId);
    await container.read(provider.notifier).refresh(oldId);
    // The authoritative detail now exposes the established successor.
    api.details[oldId] = jobDetail(
      id: 'a' * 32,
      state: JobLifecycleState.failed,
      canRetry: false,
      retrySuccessorJobRunId: successorId,
    );
    final navigated = <JobRunId>[];
    await container
        .read(provider.notifier)
        .retry(oldId, onAdmitted: navigated.add);
    expect(api.retryCalls, 1);
    expect(navigated, [successorId]);
  });

  test('active summary distinguishes zero one and multiple', () async {
    final zero = createContainer(FakeJobsApi());
    expect(
      await zero.read(jobsApiProvider).getActiveJobSummary(),
      const ActiveJobSummary(activeCount: 0),
    );

    final one = createContainer(
      FakeJobsApi(activeJobs: [jobItem(id: 'a' * 32)]),
    );
    final summary = await one.read(jobsApiProvider).getActiveJobSummary();
    expect(summary.activeCount, 1);
    expect(summary.soleActiveJobRunId, JobRunId('a' * 32));

    final many = createContainer(
      FakeJobsApi(
        activeJobs: [
          jobItem(id: 'a' * 32),
          jobItem(id: 'b' * 32),
        ],
      ),
    );
    expect(
      (await many.read(jobsApiProvider).getActiveJobSummary()).activeCount,
      2,
    );
  });

  testWidgets('Jobs landing renders active, recent, and navigates rows', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final opened = <JobRunId>[];
      final api = FakeJobsApi(
        activeJobs: [
          jobItem(id: 'a' * 32),
          jobItem(id: 'c' * 32),
        ],
        recentJobs: [jobItem(id: 'b' * 32, state: JobLifecycleState.completed)],
      );
      final container = createContainer(api);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: JobsPage(onOpenJob: opened.add)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Recent'), findsOneWidget);
      final firstJob = tester.getSemantics(
        find.bySemanticsIdentifier('job-run:${'a' * 32}'),
      );
      final secondJob = tester.getSemantics(
        find.bySemanticsIdentifier('job-run:${'c' * 32}'),
      );
      expect(firstJob.id, isNot(secondJob.id));
      expect(
        firstJob.getSemanticsData().label,
        secondJob.getSemanticsData().label,
      );
      expect(firstJob.getSemanticsData().label, isNot(contains('a' * 32)));
      expect(find.text('Library Scan'), findsNWidgets(3));
      await tester.tap(find.byKey(ValueKey<String>('jobs-row-${'a' * 32}')));
      expect(opened, [JobRunId('a' * 32)]);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Jobs landing empty state explains long-running work', (
    tester,
  ) async {
    final container = createContainer(FakeJobsApi());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: JobsPage(onOpenJob: _noop)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No jobs yet'), findsOneWidget);
  });

  testWidgets('job detail renders factual progress and Retry only when '
      'authorized', (tester) async {
    final jobId = JobRunId('a' * 32);
    final api = FakeJobsApi(
      details: {
        jobId: jobDetail(
          id: 'a' * 32,
          state: JobLifecycleState.completedWithIssues,
          canRetry: true,
          entriesObserved: 12,
          entriesCommitted: 10,
          issueCount: 1,
        ),
      },
    );
    final container = createContainer(api);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: JobDetailPage(
            jobRunId: jobId,
            onMissingJob: () {},
            onOpenJob: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Completed with issues'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('jobs-retry-job')),
      findsOneWidget,
    );
    expect(find.text('Entries observed: 12'), findsOneWidget);
    expect(find.text('Entries committed: 10'), findsOneWidget);
    expect(find.text('Issues: 1'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.byKey(const ValueKey<String>('jobs-cancel-job')), findsNothing);
  });

  testWidgets('failed Library refresh shows historical child scan outcomes', (
    tester,
  ) async {
    final jobId = JobRunId('d' * 32);
    const hostileReason = '/private/test/path SELECT * FROM credentials';
    final scans = [
      ScanRunSummary(
        scanRunId: const ScanRunId('11111111111111111111111111111111'),
        jobRunId: jobId,
        libraryRootId: LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
        displayName: 'Games',
        safeLocationDisplay: '/library/Games',
        status: JobScanStatus.failed,
        startedAtMs: 1,
        failureReason: 'execution_host_timeout',
      ),
      ScanRunSummary(
        scanRunId: const ScanRunId('22222222222222222222222222222222'),
        jobRunId: jobId,
        libraryRootId: LibraryRootId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
        displayName: 'ROMs',
        safeLocationDisplay: '/library/ROMs',
        status: JobScanStatus.failed,
        startedAtMs: 2,
      ),
      ScanRunSummary(
        scanRunId: const ScanRunId('33333333333333333333333333333333'),
        jobRunId: jobId,
        libraryRootId: LibraryRootId('cccccccccccccccccccccccccccccccc'),
        displayName: 'BIOS',
        safeLocationDisplay: '/library/BIOS',
        status: JobScanStatus.failed,
        startedAtMs: 3,
        failureReason: 'future_producer_reason',
      ),
      ScanRunSummary(
        scanRunId: const ScanRunId('44444444444444444444444444444444'),
        jobRunId: jobId,
        libraryRootId: LibraryRootId('dddddddddddddddddddddddddddddddd'),
        displayName: 'Extras',
        safeLocationDisplay: '/library/Extras',
        status: JobScanStatus.failed,
        startedAtMs: 4,
        failureReason: hostileReason,
      ),
      ScanRunSummary(
        scanRunId: const ScanRunId('55555555555555555555555555555555'),
        jobRunId: jobId,
        libraryRootId: LibraryRootId('eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'),
        displayName: 'Arcade',
        safeLocationDisplay: '/library/Arcade',
        status: JobScanStatus.complete,
        startedAtMs: 5,
        failureReason: 'execution_host_lost',
      ),
    ];
    final detail = JobDetail(
      job: JobRunProjection(
        jobRunId: jobId,
        operationType: 'library_refresh',
        lifecycleState: JobLifecycleState.failed,
        phase: 'library_refresh.completed',
        completedUnits: 4,
        totalUnits: 5,
        statusKey: 'failed',
        createdAtMs: 1,
        cancellationRequested: false,
        controls: const JobControlAvailability(
          canCancel: false,
          canRetry: true,
        ),
      ),
      operationDetail: OperationDetail.libraryRefresh(
        LibraryRefreshJobDetail(
          trigger: 'manual',
          mode: 'eligible_only',
          requestedRootIds: scans.map((scan) => scan.libraryRootId).toList(),
          scanRuns: scans,
          exclusions: const [],
          rootOutcomeCoverage:
              LibraryRefreshRootOutcomeCoverage.historicalUnavailable,
          progress: const RefreshProgressFacts(
            phase: 'library_refresh.completed',
            completedUnits: 4,
            totalUnits: 5,
            statusKey: 'failed',
            issues: [],
          ),
        ),
      ),
    );
    final api = FakeJobsApi(details: {jobId: detail});
    final container = createContainer(api);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: JobDetailPage(
            jobRunId: jobId,
            onMissingJob: () {},
            onOpenJob: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Library refresh'), findsOneWidget);
    expect(find.text('Failed'), findsAtLeastNWidgets(1));
    expect(find.text('Trigger: manual'), findsOneWidget);
    expect(find.text('Mode: eligible_only'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, JobsMessages.retryJob),
      findsOneWidget,
    );
    Finder scanTile(String title) =>
        find.ancestor(of: find.text(title), matching: find.byType(ListTile));
    expect(
      find.descendant(
        of: scanTile('Games'),
        matching: find.text(
          'The scan stopped because its execution host timed out.',
        ),
      ),
      findsOneWidget,
    );
    for (final title in ['ROMs', 'BIOS', 'Extras']) {
      expect(
        find.descendant(
          of: scanTile(title),
          matching: find.text(JobsMessages.scanFailureUnknown),
        ),
        findsOneWidget,
      );
    }
    expect(find.text(JobsMessages.scanFailureUnknown), findsNWidgets(3));
    expect(find.text(hostileReason), findsNothing);
    expect(find.text('future_producer_reason'), findsNothing);
    final arcadeTile = scanTile('Arcade');
    expect(
      find.descendant(
        of: arcadeTile,
        matching: find.text(
          JobsMessages.scanFailureReasonLabel('execution_host_lost'),
        ),
      ),
      findsNothing,
    );
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data)
        .toList();
    expect(titles, ['Games', 'ROMs', 'BIOS', 'Extras', 'Arcade']);
  });

  testWidgets(
    'Complete Library refresh keeps each scan and exclusion identity separate',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final jobId = JobRunId('d' * 32);
        const firstRoot = LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
        const secondRoot = LibraryRootId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
        const excludedRoot = LibraryRootId('cccccccccccccccccccccccccccccccc');
        const firstScan = ScanRunId('11111111111111111111111111111111');
        const secondScan = ScanRunId('22222222222222222222222222222222');
        final excludedActiveJob = JobRunId('e' * 32);
        const excludedActiveScan = ScanRunId(
          'ffffffffffffffffffffffffffffffff',
        );
        final scans = [
          ScanRunSummary(
            scanRunId: firstScan,
            jobRunId: jobId,
            libraryRootId: firstRoot,
            displayName: 'Games',
            safeLocationDisplay: '/library/First',
            status: JobScanStatus.failed,
            startedAtMs: 1,
          ),
          ScanRunSummary(
            scanRunId: secondScan,
            jobRunId: jobId,
            libraryRootId: secondRoot,
            displayName: 'Games',
            safeLocationDisplay: '/library/Second',
            status: JobScanStatus.failed,
            startedAtMs: 2,
          ),
        ];
        final exclusion = LibraryScanAdmissionExclusion(
          libraryRootId: excludedRoot,
          reason: 'already_scanning',
          activeJobRunId: excludedActiveJob,
          activeScanRunId: excludedActiveScan,
        );
        final detail = _completeRefreshAttempt(
          jobRunId: jobId,
          requestedRootIds: const [excludedRoot, secondRoot, firstRoot],
          scanRuns: scans,
          exclusions: [exclusion],
        );
        final container = createContainer(
          FakeJobsApi(details: {jobId: detail}),
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: JobDetailPage(
                jobRunId: jobId,
                onMissingJob: () {},
                onOpenJob: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Folder coverage: complete.'), findsOneWidget);
        expect(find.text('Games'), findsNWidgets(2));
        expect(find.text('Library folder'), findsOneWidget);
        expect(find.text('Already being scanned'), findsOneWidget);
        expect(
          tester
              .widgetList<ListTile>(find.byType(ListTile))
              .map((tile) => (tile.title! as Text).data)
              .toList(),
          ['Library folder', 'Games', 'Games'],
        );
        expect(find.textContaining(jobId.value), findsNothing);
        expect(find.textContaining(firstScan.value), findsNothing);
        expect(find.textContaining(excludedRoot.value), findsNothing);

        final jobNode = tester.getSemantics(
          find.bySemanticsIdentifier('job-run:${jobId.value}'),
        );
        final firstScanNode = tester.getSemantics(
          find.bySemanticsIdentifier('scan-run:${firstScan.value}'),
        );
        final secondScanNode = tester.getSemantics(
          find.bySemanticsIdentifier('scan-run:${secondScan.value}'),
        );
        final firstRootNode = tester.getSemantics(
          find.bySemanticsIdentifier('library-root:${firstRoot.value}'),
        );
        final secondRootNode = tester.getSemantics(
          find.bySemanticsIdentifier('library-root:${secondRoot.value}'),
        );
        final excludedRootNode = tester.getSemantics(
          find.bySemanticsIdentifier('library-root:${excludedRoot.value}'),
        );
        expect(_isDescendantOf(firstScanNode, jobNode), isTrue);
        expect(_isDescendantOf(secondScanNode, jobNode), isTrue);
        expect(_isDescendantOf(firstRootNode, firstScanNode), isTrue);
        expect(_isDescendantOf(secondRootNode, secondScanNode), isTrue);
        expect(_isDescendantOf(excludedRootNode, jobNode), isTrue);
        expect(
          find.bySemanticsIdentifier('scan-run:${excludedActiveScan.value}'),
          findsNothing,
        );
        expect(
          find.bySemanticsIdentifier('job-run:${excludedActiveJob.value}'),
          findsNothing,
        );
        final firstLabel = tester
            .getSemantics(find.text('Games').first)
            .getSemanticsData()
            .label;
        final secondLabel = tester
            .getSemantics(find.text('Games').last)
            .getSemanticsData()
            .label;
        expect(firstLabel, secondLabel);
        expect(firstLabel, isNot(contains(jobId.value)));
        expect(firstLabel, isNot(contains(firstScan.value)));
        expect(jobNode.getSemanticsData().label, isNot(contains(jobId.value)));
        expect(
          secondScanNode.getSemanticsData().label,
          isNot(contains(secondScan.value)),
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'Complete coverage renders only admitted and excluded requested outcomes',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final jobId = JobRunId('d' * 32);
        const admittedRoot = LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
        const excludedRoot = LibraryRootId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
        const unrelatedRoot = LibraryRootId('cccccccccccccccccccccccccccccccc');
        const scanId = ScanRunId('11111111111111111111111111111111');
        final detail = _completeRefreshAttempt(
          jobRunId: jobId,
          requestedRootIds: const [admittedRoot, excludedRoot],
          scanRuns: [_refreshScan(scanId.value, jobId, admittedRoot)],
          exclusions: const [
            LibraryScanAdmissionExclusion(
              libraryRootId: excludedRoot,
              reason: 'already_scanning',
            ),
          ],
        );
        final container = createContainer(
          FakeJobsApi(details: {jobId: detail}),
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: JobDetailPage(
                jobRunId: jobId,
                onMissingJob: () {},
                onOpenJob: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Folder coverage: complete.'), findsOneWidget);
        expect(
          find.text('Some historical folder outcomes are unavailable.'),
          findsNothing,
        );
        expect(find.text('Games'), findsOneWidget);
        expect(find.text('Library folder'), findsOneWidget);
        expect(find.text('Already being scanned'), findsOneWidget);
        expect(
          find.bySemanticsIdentifier('scan-run:${scanId.value}'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsIdentifier('library-root:${admittedRoot.value}'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsIdentifier('library-root:${excludedRoot.value}'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsIdentifier('library-root:${unrelatedRoot.value}'),
          findsNothing,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'HistoricalUnavailable retains known outcomes without filling missing roots',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final jobId = JobRunId('d' * 32);
        const knownRoot = LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
        const excludedRoot = LibraryRootId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
        const unavailableRoot = LibraryRootId(
          'cccccccccccccccccccccccccccccccc',
        );
        const scanId = ScanRunId('11111111111111111111111111111111');
        final activeJob = JobRunId('e' * 32);
        const activeScan = ScanRunId('ffffffffffffffffffffffffffffffff');
        final detail = _rawRefreshAttempt(
          jobRunId: jobId,
          requestedRootIds: const [knownRoot, excludedRoot, unavailableRoot],
          scanRuns: [
            ScanRunSummary(
              scanRunId: scanId,
              jobRunId: jobId,
              libraryRootId: knownRoot,
              displayName: 'Recovered folder',
              safeLocationDisplay: '/library/Recovered',
              status: JobScanStatus.partial,
              startedAtMs: 1,
            ),
          ],
          exclusions: [
            LibraryScanAdmissionExclusion(
              libraryRootId: excludedRoot,
              reason: 'already_scanning',
              activeJobRunId: activeJob,
              activeScanRunId: activeScan,
            ),
          ],
          coverage: LibraryRefreshRootOutcomeCoverage.historicalUnavailable,
        );
        final container = createContainer(
          FakeJobsApi(details: {jobId: detail}),
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: JobDetailPage(
                jobRunId: jobId,
                onMissingJob: () {},
                onOpenJob: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Some historical folder outcomes are unavailable.'),
          findsOneWidget,
        );
        expect(find.text('Recovered folder'), findsOneWidget);
        expect(find.text('Library folder'), findsOneWidget);
        expect(find.text('Already being scanned'), findsOneWidget);
        expect(find.text('Unavailable folder'), findsNothing);
        expect(
          find.bySemanticsIdentifier('library-root:${unavailableRoot.value}'),
          findsNothing,
        );
        final jobNode = tester.getSemantics(
          find.bySemanticsIdentifier('job-run:${jobId.value}'),
        );
        final scanNode = tester.getSemantics(
          find.bySemanticsIdentifier('scan-run:${scanId.value}'),
        );
        final knownRootNode = tester.getSemantics(
          find.bySemanticsIdentifier('library-root:${knownRoot.value}'),
        );
        final excludedRootNode = tester.getSemantics(
          find.bySemanticsIdentifier('library-root:${excludedRoot.value}'),
        );
        expect(_isDescendantOf(scanNode, jobNode), isTrue);
        expect(_isDescendantOf(knownRootNode, scanNode), isTrue);
        expect(_isDescendantOf(excludedRootNode, jobNode), isTrue);
        expect(
          find.bySemanticsIdentifier('scan-run:${activeScan.value}'),
          findsNothing,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'HistoricalUnavailable retains unmatched outcomes and requested order',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        addTearDown(tester.view.reset);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1100, 1900);
        final jobId = JobRunId('d' * 32);
        const rootA = LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
        const rootB = LibraryRootId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
        const excludedRoot = LibraryRootId('cccccccccccccccccccccccccccccccc');
        const unknownRoot = LibraryRootId('dddddddddddddddddddddddddddddddd');
        const unmatchedScanRoot = LibraryRootId(
          'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
        );
        const unmatchedExcludedRoot = LibraryRootId(
          'ffffffffffffffffffffffffffffffff',
        );
        const scanA = ScanRunId('11111111111111111111111111111111');
        const scanB = ScanRunId('22222222222222222222222222222222');
        const scanExtra = ScanRunId('33333333333333333333333333333333');
        ScanRunSummary record(
          ScanRunId scanId,
          LibraryRootId rootId,
          String name,
        ) => ScanRunSummary(
          scanRunId: scanId,
          jobRunId: jobId,
          libraryRootId: rootId,
          displayName: name,
          safeLocationDisplay: '/library/test',
          status: JobScanStatus.complete,
          startedAtMs: 1,
        );
        final detail = _rawRefreshAttempt(
          jobRunId: jobId,
          requestedRootIds: const [rootB, rootA, excludedRoot, unknownRoot],
          scanRuns: [
            record(scanA, rootA, 'Requested A'),
            record(scanExtra, unmatchedScanRoot, 'Unmatched scan'),
            record(scanB, rootB, 'Requested B'),
          ],
          exclusions: const [
            LibraryScanAdmissionExclusion(
              libraryRootId: unmatchedExcludedRoot,
              reason: 'invalid_configuration',
            ),
            LibraryScanAdmissionExclusion(
              libraryRootId: excludedRoot,
              reason: 'already_scanning',
            ),
          ],
          coverage: LibraryRefreshRootOutcomeCoverage.historicalUnavailable,
        );
        final container = createContainer(
          FakeJobsApi(details: {jobId: detail}),
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: JobDetailPage(
                jobRunId: jobId,
                onMissingJob: () {},
                onOpenJob: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Some historical folder outcomes are unavailable.'),
          findsOneWidget,
        );
        expect(
          tester
              .widgetList<ListTile>(find.byType(ListTile))
              .map((tile) => (tile.title! as Text).data)
              .toList(),
          [
            'Requested B',
            'Requested A',
            'Library folder',
            'Unmatched scan',
            'Library folder',
          ],
        );
        expect(find.text('Already being scanned'), findsOneWidget);
        expect(find.text('Invalid configuration'), findsOneWidget);
        expect(
          find.bySemanticsIdentifier('library-root:${unknownRoot.value}'),
          findsNothing,
        );
        final parent = tester.getSemantics(
          find.bySemanticsIdentifier('job-run:${jobId.value}'),
        );
        for (final id in [scanA, scanB, scanExtra]) {
          final child = tester.getSemantics(
            find.bySemanticsIdentifier('scan-run:${id.value}'),
          );
          expect(_isDescendantOf(child, parent), isTrue);
        }
        final extraScanNode = tester.getSemantics(
          find.bySemanticsIdentifier('scan-run:${scanExtra.value}'),
        );
        final extraRootNode = tester.getSemantics(
          find.bySemanticsIdentifier('library-root:${unmatchedScanRoot.value}'),
        );
        final extraExclusionNode = tester.getSemantics(
          find.bySemanticsIdentifier(
            'library-root:${unmatchedExcludedRoot.value}',
          ),
        );
        expect(_isDescendantOf(extraRootNode, extraScanNode), isTrue);
        expect(_isDescendantOf(extraExclusionNode, parent), isTrue);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'Library refresh retry lineage navigates exact attempts and keeps root intent',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final sourceId = JobRunId('a' * 32);
        final currentId = JobRunId('b' * 32);
        final successorId = JobRunId('c' * 32);
        const firstRoot = LibraryRootId('11111111111111111111111111111111');
        const secondRoot = LibraryRootId('22222222222222222222222222222222');
        const requestedRoots = [firstRoot, secondRoot];
        final sourceScans = [
          _refreshScan('31111111111111111111111111111111', sourceId, firstRoot),
          _refreshScan(
            '32222222222222222222222222222222',
            sourceId,
            secondRoot,
          ),
        ];
        final currentScans = [
          _refreshScan(
            '41111111111111111111111111111111',
            currentId,
            firstRoot,
          ),
          _refreshScan(
            '42222222222222222222222222222222',
            currentId,
            secondRoot,
          ),
        ];
        final successorScans = [
          _refreshScan(
            '51111111111111111111111111111111',
            successorId,
            firstRoot,
          ),
          _refreshScan(
            '52222222222222222222222222222222',
            successorId,
            secondRoot,
          ),
        ];
        final source = _completeRefreshAttempt(
          jobRunId: sourceId,
          requestedRootIds: requestedRoots,
          scanRuns: sourceScans,
          retrySuccessorJobRunId: currentId,
        );
        final current = _completeRefreshAttempt(
          jobRunId: currentId,
          requestedRootIds: requestedRoots,
          scanRuns: currentScans,
          retrySourceJobRunId: sourceId,
          retrySuccessorJobRunId: successorId,
        );
        final successor = _completeRefreshAttempt(
          jobRunId: successorId,
          requestedRootIds: requestedRoots,
          scanRuns: successorScans,
          retrySourceJobRunId: currentId,
        );
        final attempts = {
          sourceId: source,
          currentId: current,
          successorId: successor,
        };
        final scanIds = [
          ...sourceScans,
          ...currentScans,
          ...successorScans,
        ].map((scan) => scan.scanRunId).toSet();
        expect(scanIds, hasLength(6));
        for (final attempt in attempts.values) {
          final refresh =
              (attempt.operationDetail as OperationDetailLibraryRefresh).detail;
          expect(refresh.requestedRootIds, requestedRoots);
        }
        final api = FakeJobsApi(details: attempts);
        final container = createContainer(api);
        var selectedJobId = currentId;
        final navigations = <JobRunId>[];

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: StatefulBuilder(
                builder: (context, setState) => JobDetailPage(
                  jobRunId: selectedJobId,
                  onMissingJob: () {},
                  onOpenJob: (jobRunId) {
                    navigations.add(jobRunId);
                    setState(() => selectedJobId = jobRunId);
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        void expectAttempt(JobRunId jobId, List<ScanRunSummary> scans) {
          expect(
            find.bySemanticsIdentifier('job-run:${jobId.value}'),
            findsOneWidget,
          );
          for (final root in requestedRoots) {
            expect(
              find.bySemanticsIdentifier('library-root:${root.value}'),
              findsOneWidget,
            );
          }
          for (final scan in scans) {
            expect(
              find.bySemanticsIdentifier('scan-run:${scan.scanRunId.value}'),
              findsOneWidget,
            );
          }
        }

        expectAttempt(currentId, currentScans);
        expect(
          find.bySemanticsIdentifier('job-run:${sourceId.value}'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsIdentifier('job-run:${successorId.value}'),
          findsOneWidget,
        );
        expect(find.textContaining(sourceId.value), findsNothing);
        expect(find.textContaining(successorId.value), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('jobs-retry-job')),
          findsNothing,
        );
        expect(find.text('Resume'), findsNothing);
        await tester.tap(find.text(JobsMessages.retriedFrom));
        await tester.pumpAndSettle();
        expect(navigations, [sourceId]);
        expectAttempt(sourceId, sourceScans);
        expect(
          find.bySemanticsIdentifier(
            'scan-run:${currentScans.first.scanRunId.value}',
          ),
          findsNothing,
        );

        await tester.tap(find.text(JobsMessages.retriedAs));
        await tester.pumpAndSettle();
        expect(navigations, [sourceId, currentId]);
        expectAttempt(currentId, currentScans);

        await tester.tap(find.text(JobsMessages.retriedAs));
        await tester.pumpAndSettle();
        expect(navigations, [sourceId, currentId, successorId]);
        expectAttempt(successorId, successorScans);
        expect(
          find.bySemanticsIdentifier(
            'scan-run:${currentScans.first.scanRunId.value}',
          ),
          findsNothing,
        );
        expect(api.retryCalls, 0);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('failed Library refresh explains incomplete folder contents', (
    tester,
  ) async {
    final jobId = JobRunId('f' * 32);
    const rootId = LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    final detail = JobDetail(
      job: JobRunProjection(
        jobRunId: jobId,
        operationType: 'library_refresh',
        lifecycleState: JobLifecycleState.failed,
        phase: 'library_refresh.completed',
        completedUnits: 1,
        totalUnits: 1,
        statusKey: 'failed',
        createdAtMs: 1,
        cancellationRequested: false,
        controls: const JobControlAvailability(
          canCancel: false,
          canRetry: true,
        ),
      ),
      operationDetail: OperationDetail.libraryRefresh(
        LibraryRefreshJobDetail(
          trigger: 'manual',
          mode: 'eligible_only',
          requestedRootIds: const [rootId],
          scanRuns: [
            ScanRunSummary(
              scanRunId: const ScanRunId('66666666666666666666666666666666'),
              jobRunId: jobId,
              libraryRootId: rootId,
              displayName: 'Games',
              safeLocationDisplay: '/library/Games',
              status: JobScanStatus.failed,
              startedAtMs: 1,
              failureReason: 'incomplete_scope',
            ),
          ],
          exclusions: const [],
          rootOutcomeCoverage:
              LibraryRefreshRootOutcomeCoverage.historicalUnavailable,
          progress: const RefreshProgressFacts(
            phase: 'library_refresh.completed',
            completedUnits: 1,
            totalUnits: 1,
            statusKey: 'failed',
            issues: [],
          ),
        ),
      ),
    );
    final api = FakeJobsApi(details: {jobId: detail});

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: createContainer(api),
        child: MaterialApp(
          home: JobDetailPage(
            jobRunId: jobId,
            onMissingJob: () {},
            onOpenJob: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Some contents of this folder could not be fully scanned.'),
      findsOneWidget,
    );
  });

  testWidgets('partial Library refresh detail explains why it finished with '
      'issues', (tester) async {
    final jobId = JobRunId('b' * 32);
    final api = FakeJobsApi(
      details: {
        jobId: libraryRefreshJobDetail(
          id: 'b' * 32,
          state: JobLifecycleState.completedWithIssues,
          statusKey: 'completed_with_issues',
          issueCount: 3,
          issues: const [
            RefreshIssueFact(
              kind: RefreshIssueKind.matching,
              reason: RefreshIssueReason.providerUnavailable,
              providerId: 'gametdb',
              occurrences: 2,
            ),
            RefreshIssueFact(
              kind: RefreshIssueKind.content,
              reason: RefreshIssueReason.contentUnavailable,
              occurrences: 1,
            ),
          ],
        ),
      },
    );
    final container = createContainer(api);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: JobDetailPage(
            jobRunId: jobId,
            onMissingJob: () {},
            onOpenJob: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Completed with issues'), findsOneWidget);
    expect(find.text('Issues: 3'), findsOneWidget);
    expect(find.text('Why this finished with issues'), findsOneWidget);
    expect(
      find.textContaining(
        'Content matching: the metadata provider was unavailable '
        '(GameTDB) (2 affected)',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Local content: admitted content could not be read'),
      findsOneWidget,
    );
  });

  testWidgets('partial Library refresh can reveal every bounded issue fact', (
    tester,
  ) async {
    final jobId = JobRunId('c' * 32);
    final api = FakeJobsApi(
      details: {
        jobId: libraryRefreshJobDetail(
          id: 'c' * 32,
          state: JobLifecycleState.completedWithIssues,
          statusKey: 'completed_with_issues',
          issueCount: 6,
          issues: const [
            RefreshIssueFact(
              kind: RefreshIssueKind.matching,
              reason: RefreshIssueReason.providerUnavailable,
              providerId: 'gametdb',
              occurrences: 1,
            ),
            RefreshIssueFact(
              kind: RefreshIssueKind.metadata,
              reason: RefreshIssueReason.providerTimeout,
              providerId: 'gametdb',
              occurrences: 1,
            ),
            RefreshIssueFact(
              kind: RefreshIssueKind.artworkDiscovery,
              reason: RefreshIssueReason.providerRateLimited,
              providerId: 'steamgriddb',
              occurrences: 1,
            ),
            RefreshIssueFact(
              kind: RefreshIssueKind.artworkDownload,
              reason: RefreshIssueReason.providerInvalidResponse,
              providerId: 'steamgriddb',
              occurrences: 1,
            ),
            RefreshIssueFact(
              kind: RefreshIssueKind.assetStore,
              reason: RefreshIssueReason.artworkAssetStoreUnavailable,
              occurrences: 1,
            ),
            RefreshIssueFact(
              kind: RefreshIssueKind.content,
              reason: RefreshIssueReason.contentUnavailable,
              occurrences: 1,
            ),
          ],
        ),
      },
    );
    final container = createContainer(api);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: JobDetailPage(
            jobRunId: jobId,
            onMissingJob: () {},
            onOpenJob: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Why this finished with issues'), findsOneWidget);
    expect(find.textContaining('Artwork storage:'), findsOneWidget);
    expect(
      find.textContaining('Local content: admitted content could not be read'),
      findsNothing,
    );
    final showAll = find.text('Show all issue details');
    expect(showAll, findsOneWidget);
    await tester.ensureVisible(showAll);
    await tester.tap(showAll);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Local content: admitted content could not be read'),
      findsOneWidget,
    );
    expect(find.text('Show fewer issue details'), findsOneWidget);
  });

  testWidgets('clean Completed job detail has no Retry control', (
    tester,
  ) async {
    final jobId = JobRunId('a' * 32);
    final api = FakeJobsApi(
      details: {
        jobId: jobDetail(id: 'a' * 32, state: JobLifecycleState.completed),
      },
    );
    final container = createContainer(api);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: JobDetailPage(
            jobRunId: jobId,
            onMissingJob: () {},
            onOpenJob: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('jobs-retry-job')), findsNothing);
    expect(find.byKey(const ValueKey<String>('jobs-cancel-job')), findsNothing);
  });

  testWidgets(
    'job detail keeps actions in an adaptive header at compact 2x text',
    (tester) async {
      addTearDown(tester.view.reset);
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;

      final jobId = JobRunId('a' * 32);
      final container = createContainer(
        FakeJobsApi(
          details: {
            jobId: jobDetail(id: 'a' * 32, state: JobLifecycleState.running),
          },
        ),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: JobDetailPage(
              jobRunId: jobId,
              onMissingJob: () {},
              onOpenJob: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('jobs-detail-header')),
        findsOneWidget,
      );
      expect(find.byType(Wrap), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('job detail renders independent multi-root outcomes', (
    tester,
  ) async {
    final jobId = JobRunId('a' * 32);
    final rootA = LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    final rootB = LibraryRootId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
    final rootC = LibraryRootId('cccccccccccccccccccccccccccccccc');
    final api = FakeJobsApi(
      details: {
        jobId: jobDetail(
          id: 'a' * 32,
          state: JobLifecycleState.completedWithIssues,
          rootsRequested: 3,
          rootsAdmitted: 3,
          rootsTerminal: 3,
          requestedRoots: const [
            LibraryScanRootSummary(
              libraryRootId: LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
              displayName: 'Games',
              safeLocationDisplay: '/library/Games',
            ),
            LibraryScanRootSummary(
              libraryRootId: LibraryRootId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
              displayName: 'ROMs',
              safeLocationDisplay: '/library/ROMs',
            ),
            LibraryScanRootSummary(
              libraryRootId: LibraryRootId('cccccccccccccccccccccccccccccccc'),
              displayName: 'BIOS',
              safeLocationDisplay: '/library/BIOS',
            ),
          ],
          scanRuns: [
            ScanRunSummary(
              scanRunId: const ScanRunId('11111111111111111111111111111111'),
              jobRunId: jobId,
              libraryRootId: rootA,
              displayName: 'Games',
              safeLocationDisplay: '/library/Games',
              status: JobScanStatus.complete,
              startedAtMs: 1,
            ),
            ScanRunSummary(
              scanRunId: const ScanRunId('22222222222222222222222222222222'),
              jobRunId: jobId,
              libraryRootId: rootB,
              displayName: 'ROMs',
              safeLocationDisplay: '/library/ROMs',
              status: JobScanStatus.failed,
              startedAtMs: 1,
              failureReason: 'execution_host_timeout',
            ),
            ScanRunSummary(
              scanRunId: const ScanRunId('33333333333333333333333333333333'),
              jobRunId: jobId,
              libraryRootId: rootC,
              displayName: 'BIOS',
              safeLocationDisplay: '/library/BIOS',
              status: JobScanStatus.partial,
              startedAtMs: 1,
              failureReason: 'incomplete_scope',
            ),
          ],
        ),
      },
    );
    final container = createContainer(api);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: JobDetailPage(
            jobRunId: jobId,
            onMissingJob: () {},
            onOpenJob: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Completed with issues'), findsOneWidget);
    expect(find.text('Roots requested: 3'), findsOneWidget);
    expect(find.text('Roots admitted: 3'), findsOneWidget);
    expect(find.text('Roots terminal: 3'), findsOneWidget);
    expect(find.text('Games'), findsWidgets);
    expect(find.text('ROMs'), findsWidgets);
    expect(find.text('BIOS'), findsWidgets);
    expect(find.text('Complete'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Partial'), findsOneWidget);
    expect(
      find.text('The scan stopped because its execution host timed out.'),
      findsOneWidget,
    );
    expect(
      find.text('Some contents of this folder could not be fully scanned.'),
      findsOneWidget,
    );
    expect(find.text('execution_host_timeout'), findsNothing);
    final failedScanTile = find.ancestor(
      of: find.text('Failed'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: failedScanTile, matching: find.text('ROMs')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: failedScanTile,
        matching: find.text(
          'The scan stopped because its execution host timed out.',
        ),
      ),
      findsOneWidget,
    );
    final partialScanTile = find.ancestor(
      of: find.text('Partial'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: partialScanTile, matching: find.text('BIOS')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: partialScanTile,
        matching: find.text(
          'Some contents of this folder could not be fully scanned.',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('job detail labels typed exclusions including bounded errors', (
    tester,
  ) async {
    final jobId = JobRunId('a' * 32);
    final api = FakeJobsApi(
      details: {
        jobId: jobDetail(
          id: 'a' * 32,
          state: JobLifecycleState.completedWithIssues,
          rootsRequested: 2,
          rootsAdmitted: 1,
          rootsTerminal: 1,
          exclusions: const [
            LibraryScanAdmissionExclusion(
              libraryRootId: LibraryRootId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
              reason: 'already_scanning',
            ),
            LibraryScanAdmissionExclusion(
              libraryRootId: LibraryRootId('cccccccccccccccccccccccccccccccc'),
              reason: 'invalid_configuration',
              applicationError: ClientApplicationError(
                code: ErrorCode('ARGUS.V1.CONFIGURATION.INVALID'),
                category: ErrorCategory.configuration,
                severity: ApplicationSeverity.error,
                recoverability: Recoverability.userAction,
                retryPolicy: RetryPolicy.never,
                messageKey: MessageKey('errors.configuration.invalid'),
                traceId: TraceId('33333333333333333333333333333333'),
                safeContext: [],
              ),
            ),
          ],
        ),
      },
    );
    final container = createContainer(api);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: JobDetailPage(
            jobRunId: jobId,
            onMissingJob: () {},
            onOpenJob: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Already being scanned'), findsOneWidget);
    expect(find.text('Invalid configuration'), findsOneWidget);
    expect(find.text('ARGUS.V1.CONFIGURATION.INVALID'), findsOneWidget);
  });

  testWidgets('removed-root history renders durable display snapshots', (
    tester,
  ) async {
    final jobId = JobRunId('a' * 32);
    final api = FakeJobsApi(
      details: {
        jobId: jobDetail(
          id: 'a' * 32,
          state: JobLifecycleState.completed,
          requestedRoots: const [
            LibraryScanRootSummary(
              libraryRootId: LibraryRootId('dddddddddddddddddddddddddddddddd'),
              displayName: 'Removed Games',
              safeLocationDisplay: '/library/RemovedGames',
            ),
          ],
        ),
      },
    );
    final container = createContainer(api);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: JobDetailPage(
            jobRunId: jobId,
            onMissingJob: () {},
            onOpenJob: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Removed Games'), findsOneWidget);
    expect(find.text('/library/RemovedGames'), findsOneWidget);
  });

  testWidgets('Scan All retry relationship navigates to the successor', (
    tester,
  ) async {
    final jobId = JobRunId('a' * 32);
    final successorId = JobRunId('b' * 32);
    JobRunId? openedJob;
    final api = FakeJobsApi(
      details: {
        jobId: jobDetail(
          id: 'a' * 32,
          state: JobLifecycleState.failed,
          retrySourceJobRunId: JobRunId('c' * 32),
          retrySuccessorJobRunId: successorId,
        ),
      },
    );
    final container = createContainer(api);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: JobDetailPage(
            jobRunId: jobId,
            onMissingJob: () {},
            onOpenJob: (jobRunId) => openedJob = jobRunId,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Retried as'));
    expect(openedJob, successorId);
  });
}

void _noop(JobRunId _) {}

// Valid Complete fixtures partition requested roots into admitted scans or typed
// exclusions. HistoricalUnavailable and intentionally malformed DTOs use the raw
// constructor below so negative tests do not accidentally acquire this invariant.
JobDetail _completeRefreshAttempt({
  required JobRunId jobRunId,
  required List<LibraryRootId> requestedRootIds,
  required List<ScanRunSummary> scanRuns,
  List<LibraryScanAdmissionExclusion> exclusions = const [],
  JobRunId? retrySourceJobRunId,
  JobRunId? retrySuccessorJobRunId,
  bool canRetry = false,
}) {
  final requested = <String>{};
  for (final root in requestedRootIds) {
    if (!requested.add(root.value)) {
      throw ArgumentError('Duplicate requested LibraryRootId');
    }
  }

  final covered = <String>{};
  final seenScanIds = <String>{};
  for (final scan in scanRuns) {
    if (scan.jobRunId.value != jobRunId.value) {
      throw ArgumentError('ScanRun belongs to a different JobRun');
    }
    if (!seenScanIds.add(scan.scanRunId.value)) {
      throw ArgumentError('Duplicate ScanRunId');
    }
    if (!requested.contains(scan.libraryRootId.value)) {
      throw ArgumentError('ScanRun belongs to an unrequested root');
    }
    if (!covered.add(scan.libraryRootId.value)) {
      throw ArgumentError('Multiple outcomes for a requested root');
    }
  }
  for (final exclusion in exclusions) {
    if (!requested.contains(exclusion.libraryRootId.value)) {
      throw ArgumentError('Exclusion belongs to an unrequested root');
    }
    if (!covered.add(exclusion.libraryRootId.value)) {
      throw ArgumentError('Multiple outcomes for a requested root');
    }
  }
  if (covered.length != requested.length) {
    throw ArgumentError('Complete coverage requires one outcome per root');
  }

  return _rawRefreshAttempt(
    jobRunId: jobRunId,
    requestedRootIds: requestedRootIds,
    scanRuns: scanRuns,
    exclusions: exclusions,
    coverage: LibraryRefreshRootOutcomeCoverage.complete,
    retrySourceJobRunId: retrySourceJobRunId,
    retrySuccessorJobRunId: retrySuccessorJobRunId,
    canRetry: canRetry,
  );
}

JobDetail _rawRefreshAttempt({
  required JobRunId jobRunId,
  required List<LibraryRootId> requestedRootIds,
  required List<ScanRunSummary> scanRuns,
  List<LibraryScanAdmissionExclusion> exclusions = const [],
  required LibraryRefreshRootOutcomeCoverage coverage,
  JobRunId? retrySourceJobRunId,
  JobRunId? retrySuccessorJobRunId,
  bool canRetry = false,
}) => JobDetail(
  job: JobRunProjection(
    jobRunId: jobRunId,
    operationType: 'library_refresh',
    lifecycleState: JobLifecycleState.failed,
    createdAtMs: 1,
    cancellationRequested: false,
    controls: JobControlAvailability(canCancel: false, canRetry: canRetry),
  ),
  operationDetail: OperationDetail.libraryRefresh(
    LibraryRefreshJobDetail(
      trigger: 'manual',
      mode: 'eligible_only',
      requestedRootIds: requestedRootIds,
      scanRuns: scanRuns,
      exclusions: exclusions,
      rootOutcomeCoverage: coverage,
      retrySourceJobRunId: retrySourceJobRunId,
      retrySuccessorJobRunId: retrySuccessorJobRunId,
      progress: const RefreshProgressFacts(issues: []),
    ),
  ),
);

ScanRunSummary _refreshScan(
  String scanRunId,
  JobRunId jobRunId,
  LibraryRootId rootId,
) => ScanRunSummary(
  scanRunId: ScanRunId(scanRunId),
  jobRunId: jobRunId,
  libraryRootId: rootId,
  displayName: 'Games',
  safeLocationDisplay: '/library/Games',
  status: JobScanStatus.complete,
  startedAtMs: 1,
);

bool _isDescendantOf(SemanticsNode node, SemanticsNode ancestor) {
  SemanticsNode? parent = node.parent;
  while (parent != null) {
    if (parent.id == ancestor.id) return true;
    parent = parent.parent;
  }
  return false;
}
