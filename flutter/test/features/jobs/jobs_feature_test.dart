import 'package:argus/core/client/client.dart';
import 'package:argus/features/jobs/jobs.dart';
import 'package:argus/features/jobs/presentation/jobs_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final opened = <JobRunId>[];
    final api = FakeJobsApi(
      activeJobs: [jobItem(id: 'a' * 32)],
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
    await tester.tap(find.byKey(ValueKey<String>('jobs-row-${'a' * 32}')));
    expect(opened, [JobRunId('a' * 32)]);
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
