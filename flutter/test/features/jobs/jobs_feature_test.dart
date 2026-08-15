import 'package:argus/core/client/client.dart';
import 'package:argus/features/jobs/jobs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'jobs_test_fakes.dart';

TransportFailure transportFailure() =>
    const TransportFailure('fake transport failure');

void main() {
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

  testWidgets('job detail renders independent multi-root outcomes', (
    tester,
  ) async {
    final jobId = JobRunId('a' * 32);
    final rootA = LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    final rootB = LibraryRootId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
    final api = FakeJobsApi(
      details: {
        jobId: jobDetail(
          id: 'a' * 32,
          state: JobLifecycleState.completedWithIssues,
          rootsRequested: 2,
          rootsAdmitted: 2,
          rootsTerminal: 2,
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
    expect(find.text('Roots requested: 2'), findsOneWidget);
    expect(find.text('Roots admitted: 2'), findsOneWidget);
    expect(find.text('Roots terminal: 2'), findsOneWidget);
    expect(find.text('Games'), findsWidgets);
    expect(find.text('ROMs'), findsWidgets);
    expect(find.text('Complete'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
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
