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
}

void _noop(JobRunId _) {}
