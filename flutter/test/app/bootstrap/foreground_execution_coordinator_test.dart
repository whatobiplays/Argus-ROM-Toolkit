import 'dart:async';

import 'package:argus/app/bootstrap/foreground_execution_coordinator.dart';
import 'package:argus/app/platform/application/foreground_execution_host_api.dart';
import 'package:argus/core/bridge/bridge.dart';
import 'package:argus/core/client/client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/jobs/jobs_test_fakes.dart' as jobs_fakes;
import '../../features/sources/sources_test_fakes.dart' as sources_fakes;

void main() {
  const admittedJobId = JobRunId('11111111111111111111111111111111');
  const activeJobId = JobRunId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
  const secondActiveJobId = JobRunId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');

  test('acquires before Add & Scan and retains an admitted lease', () async {
    final host = FakeForegroundHost();
    final sources = sources_fakes.FakeSourcesApi();
    final jobs = jobs_fakes.FakeJobsApi(
      activeJobs: [jobs_fakes.jobItem(id: admittedJobId.value)],
    );
    var admissionSawLease = false;
    sources.onAddAndScan = (selection) {
      admissionSawLease = host.leases.isNotEmpty;
      return AddLocalLibraryRootAndScanResult.addedAndScanAdmitted(
        root: sources_fakes.fakeRoot(id: 'cccccccccccccccccccccccccccccccc'),
        handle: const OperationHandle(
          jobRunId: admittedJobId,
          operationType: 'library_scan',
        ),
      );
    };
    final coordinator = makeCoordinator(host, sources, jobs);

    final result = await coordinator.sourcesApi.addLocalLibraryRootAndScan(
      LocalFilesystemRootSelection.path('/library/Games'),
    );

    expect(result, isA<AddLocalLibraryRootAndScanResultAddedAndScanAdmitted>());
    expect(admissionSawLease, isTrue);
    expect(host.acquireCalls, 1);
    expect(host.leases, hasLength(1));
    await coordinator.dispose();
  });

  test(
    'serializes direct admissions while reconciliation is in flight',
    () async {
      final host = FakeForegroundHost();
      final sources = sources_fakes.FakeSourcesApi();
      final jobs = jobs_fakes.FakeJobsApi(
        activeJobs: [jobs_fakes.jobItem(id: admittedJobId.value)],
      );
      final listStarted = Completer<void>();
      final releaseList = Completer<void>();
      var firstList = true;
      jobs.listGate = () async {
        if (!firstList) return;
        firstList = false;
        listStarted.complete();
        await releaseList.future;
      };
      final coordinator = makeCoordinator(host, sources, jobs);

      final first = coordinator.sourcesApi.addLocalLibraryRootAndScan(
        LocalFilesystemRootSelection.path('/library/First'),
      );
      await listStarted.future;
      final second = coordinator.sourcesApi.addLocalLibraryRootAndScan(
        LocalFilesystemRootSelection.path('/library/Second'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(sources.addAndScanCalls, 1);
      releaseList.complete();
      await Future.wait([first, second]);

      expect(sources.addAndScanCalls, 2);
      expect(host.acquireCalls, 2);
      await coordinator.dispose();
    },
  );

  test('acquires before Start Scan and retains an admitted lease', () async {
    final host = FakeForegroundHost();
    final sources = sources_fakes.FakeSourcesApi();
    final jobs = jobs_fakes.FakeJobsApi(
      activeJobs: [jobs_fakes.jobItem(id: admittedJobId.value)],
    );
    var admissionSawLease = false;
    sources.onStartScan = (_) {
      admissionSawLease = host.leases.isNotEmpty;
      return const StartLibraryScanResult.admitted(
        OperationHandle(jobRunId: admittedJobId, operationType: 'library_scan'),
      );
    };
    final coordinator = makeCoordinator(host, sources, jobs);

    final result = await coordinator.sourcesApi.startLibraryScan(
      const LibraryRootId('cccccccccccccccccccccccccccccccc'),
    );

    expect(result, isA<StartLibraryScanResultAdmitted>());
    expect(admissionSawLease, isTrue);
    expect(sources.startScanCalls, 1);
    expect(host.acquireCalls, 1);
    expect(host.leases, hasLength(1));
    await coordinator.dispose();
  });

  test('lease acquisition failure prevents durable admission', () async {
    final host = FakeForegroundHost()
      ..acquireFailure = const TransportFailure('foreground unavailable');
    final sources = sources_fakes.FakeSourcesApi();
    final jobs = jobs_fakes.FakeJobsApi();
    final coordinator = makeCoordinator(host, sources, jobs);

    await expectLater(
      coordinator.sourcesApi.addLocalLibraryRootAndScan(
        LocalFilesystemRootSelection.path('/library/Games'),
      ),
      throwsA(isA<TransportFailure>()),
    );

    expect(sources.addAndScanCalls, 0);
    await coordinator.dispose();
  });

  test('Scan All remains raw pass-through', () async {
    final host = FakeForegroundHost();
    final sources = sources_fakes.FakeSourcesApi();
    sources.onStartScanAll = (request) =>
        const StartLibraryScanAllResult.nothingEligible(exclusions: []);
    final coordinator = makeCoordinator(
      host,
      sources,
      jobs_fakes.FakeJobsApi(),
    );

    await coordinator.sourcesApi.startLibraryScanAll(
      const ScanAllRequestIdentity('request-1'),
    );

    expect(host.acquireCalls, 0);
    expect(sources.startScanAllCalls, 1);
    await coordinator.dispose();
  });

  test('Library refresh acquires the existing foreground lease', () async {
    final host = FakeForegroundHost();
    final refresh = FakeLibraryRefreshApi();
    var admissionSawLease = false;
    refresh.onRefresh = () async {
      admissionSawLease = host.leases.isNotEmpty;
      return const OperationHandle(
        jobRunId: admittedJobId,
        operationType: 'library_refresh',
      );
    };
    final coordinator = makeCoordinator(
      host,
      sources_fakes.FakeSourcesApi(),
      jobs_fakes.FakeJobsApi(
        activeJobs: [jobs_fakes.jobItem(id: admittedJobId.value)],
      ),
      refresh: refresh,
    );

    final result = await coordinator.refreshApi.refreshLibrary();

    expect(result.operationType, 'library_refresh');
    expect(admissionSawLease, isTrue);
    expect(host.acquireCalls, 1);
    expect(host.leases, hasLength(1));
    await coordinator.dispose();
  });

  test(
    'retry acquires only after authoritative LibraryScan retryability',
    () async {
      final host = FakeForegroundHost();
      final jobs = jobs_fakes.FakeJobsApi();
      const retryId = JobRunId('dddddddddddddddddddddddddddddddd');
      jobs.details[retryId] = jobs_fakes.jobDetail(
        id: retryId.value,
        canRetry: true,
      );
      final coordinator = makeCoordinator(
        host,
        sources_fakes.FakeSourcesApi(),
        jobs,
      );

      await coordinator.jobsApi.retryJob(retryId);

      expect(jobs.getCalls, 1);
      expect(jobs.retryCalls, 1);
      expect(host.acquireCalls, 1);
      await coordinator.dispose();
    },
  );

  test(
    'non-LibraryScan retry stays raw and does not acquire a lease',
    () async {
      final host = FakeForegroundHost();
      final jobs = jobs_fakes.FakeJobsApi();
      const retryId = JobRunId('eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee');
      final detail = jobs_fakes.jobDetail(id: retryId.value, canRetry: true);
      jobs.details[retryId] = detail.copyWith(
        job: detail.job.copyWith(operationType: 'other_operation'),
      );
      final coordinator = makeCoordinator(
        host,
        sources_fakes.FakeSourcesApi(),
        jobs,
      );

      await coordinator.jobsApi.retryJob(retryId);

      expect(jobs.getCalls, 1);
      expect(jobs.retryCalls, 1);
      expect(host.acquireCalls, 0);
      await coordinator.dispose();
    },
  );

  test('Add & Scan transport ambiguity is admitted exactly once', () async {
    final host = FakeForegroundHost();
    final sources = sources_fakes.FakeSourcesApi();
    sources.onAddAndScan = (_) {
      throw const TransportFailure(
        'Composite transport response was ambiguous',
        kind: TransportFailureKind.communicationFailed,
      );
    };
    final jobs = jobs_fakes.FakeJobsApi();
    final coordinator = makeCoordinator(host, sources, jobs);

    await expectLater(
      coordinator.sourcesApi.addLocalLibraryRootAndScan(
        LocalFilesystemRootSelection.path('/library/Games'),
      ),
      throwsA(isA<TransportFailure>()),
    );

    expect(sources.addAndScanCalls, 1);
    expect(jobs.activeCalls, 1);
    expect(host.acquireCalls, 1);
    expect(host.leases, isEmpty);
    await coordinator.dispose();
  });

  test(
    'timeout reports host stop and never calls durable cancellation',
    () async {
      final host = FakeForegroundHost();
      final jobs = jobs_fakes.FakeJobsApi(
        activeJobs: [jobs_fakes.jobItem(id: activeJobId.value)],
      );
      final stopReasons = <ExecutionHostStopReason>[];
      final coordinator = makeCoordinator(
        host,
        sources_fakes.FakeSourcesApi(),
        jobs,
        onHostStop: ({required jobRunIds, required reason}) async {
          expect(jobRunIds, [activeJobId]);
          stopReasons.add(reason);
        },
      );

      host.emit(const ForegroundExecutionTimedOut());
      await pumpCoordinator();

      expect(stopReasons, [ExecutionHostStopReason.timeout]);
      expect(jobs.cancelCalls, 0);
      await coordinator.dispose();
    },
  );

  test('native cancel uses raw Jobs cancellation exactly once', () async {
    final host = FakeForegroundHost();
    final events = FakeEventsApi();
    final jobs = jobs_fakes.FakeJobsApi();
    final coordinator = makeCoordinator(
      host,
      sources_fakes.FakeSourcesApi(),
      jobs,
      events: events,
    );

    host.emit(const ForegroundExecutionCancelRequested(activeJobId));
    host.emit(const ForegroundExecutionCancelRequested(activeJobId));
    await pumpCoordinator();

    expect(jobs.cancelCalls, 1);
    await coordinator.dispose();
  });

  test(
    'active jobs beyond retained leases report loss without acquiring',
    () async {
      final host = FakeForegroundHost();
      final jobs = jobs_fakes.FakeJobsApi(
        activeJobs: [
          jobs_fakes.jobItem(id: activeJobId.value),
          jobs_fakes.jobItem(id: secondActiveJobId.value),
        ],
      );
      final reported = <JobRunId>[];
      final coordinator = makeCoordinator(
        host,
        sources_fakes.FakeSourcesApi(),
        jobs,
        onHostStop: ({required jobRunIds, required reason}) async {
          reported.addAll(jobRunIds);
          expect(reason, ExecutionHostStopReason.hostLost);
        },
      );

      host.emit(const ForegroundExecutionHostLost());
      await pumpCoordinator();

      expect(host.acquireCalls, 0);
      expect(reported, [activeJobId, secondActiveJobId]);
      await coordinator.dispose();
    },
  );

  test('terminal authoritative state releases the final lease', () async {
    final host = FakeForegroundHost();
    final events = FakeEventsApi();
    final sources = sources_fakes.FakeSourcesApi();
    final jobs = jobs_fakes.FakeJobsApi(
      activeJobs: [jobs_fakes.jobItem(id: admittedJobId.value)],
    );
    sources.onAddAndScan = (selection) =>
        AddLocalLibraryRootAndScanResult.addedAndScanAdmitted(
          root: sources_fakes.fakeRoot(id: 'cccccccccccccccccccccccccccccccc'),
          handle: const OperationHandle(
            jobRunId: admittedJobId,
            operationType: 'library_scan',
          ),
        );
    final coordinator = makeCoordinator(host, sources, jobs, events: events);

    await coordinator.sourcesApi.addLocalLibraryRootAndScan(
      LocalFilesystemRootSelection.path('/library/Games'),
    );
    expect(host.leases, hasLength(1));

    jobs.activeJobs = [];
    events.emit(
      RuntimeEvent(
        runtimeInstanceId: RuntimeInstanceId(
          '11111111111111111111111111111111',
        ),
        sequence: BigInt.one,
        occurredAtMs: BigInt.one,
        payload: const RuntimeEventPayload.jobStateChanged(
          jobRunId: admittedJobId,
        ),
      ),
    );
    await pumpCoordinator();

    expect(host.leases, isEmpty);
    expect(host.projections.last.activeJobCount, 0);
    await coordinator.dispose();
  });
}

ForegroundExecutionCoordinator makeCoordinator(
  FakeForegroundHost host,
  SourcesApi sources,
  JobsApi jobs, {
  LibraryRefreshApi? refresh,
  FakeEventsApi? events,
  Future<void> Function({
    required List<JobRunId> jobRunIds,
    required ExecutionHostStopReason reason,
  })?
  onHostStop,
}) => ForegroundExecutionCoordinator(
  sources: sources,
  jobs: jobs,
  refresh: refresh ?? FakeLibraryRefreshApi(),
  events: events ?? FakeEventsApi(),
  host: host,
  executionHostControl: FrbExecutionHostControl(
    report: onHostStop ?? ({required jobRunIds, required reason}) async {},
  ),
);

Future<void> pumpCoordinator() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class FakeForegroundHost implements ForegroundExecutionHostApi {
  final controller = StreamController<ForegroundExecutionHostEvent>.broadcast();
  final leases = <ForegroundExecutionLease>[];
  final projections = <ForegroundExecutionProjection>[];
  Object? acquireFailure;
  int acquireCalls = 0;
  int _nextLease = 1;

  @override
  Stream<ForegroundExecutionHostEvent> get events => controller.stream;

  @override
  Future<ForegroundExecutionLease> acquireLibraryScanLease() async {
    acquireCalls++;
    final failure = acquireFailure;
    if (failure != null) throw failure;
    final lease = ForegroundExecutionLease('lease-${_nextLease++}');
    leases.add(lease);
    return lease;
  }

  @override
  Future<void> releaseLease(ForegroundExecutionLease lease) async {
    leases.remove(lease);
  }

  @override
  Future<void> updateProjection(
    ForegroundExecutionProjection projection,
  ) async {
    projections.add(projection);
  }

  void emit(ForegroundExecutionHostEvent event) {
    controller.add(event);
  }
}

final class FakeEventsApi implements EventsApi {
  final controller = StreamController<RuntimeEvent>.broadcast();

  @override
  Stream<RuntimeEvent> get events => controller.stream;

  void emit(RuntimeEvent event) => controller.add(event);
}

final class FakeLibraryRefreshApi implements LibraryRefreshApi {
  Future<OperationHandle> Function()? onRefresh;
  Future<OperationHandle> Function(List<GameId>, RefreshMode)? onGameRefresh;

  @override
  Future<OperationHandle> refreshLibrary() =>
      onRefresh?.call() ??
      Future.value(
        OperationHandle(
          jobRunId: JobRunId('cccccccccccccccccccccccccccccccc'),
          operationType: 'library_refresh',
        ),
      );

  @override
  Future<OperationHandle> startGameRefresh({
    required List<GameId> gameIds,
    required RefreshMode mode,
  }) =>
      onGameRefresh?.call(gameIds, mode) ??
      Future.value(
        OperationHandle(
          jobRunId: JobRunId('dddddddddddddddddddddddddddddddd'),
          operationType: 'game_refresh',
        ),
      );
}
