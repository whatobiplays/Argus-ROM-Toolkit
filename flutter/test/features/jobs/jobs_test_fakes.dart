import 'package:argus/core/client/client.dart';

/// Deterministic focused Jobs API fake.
final class FakeJobsApi implements JobsApi {
  FakeJobsApi({
    List<JobListItem>? activeJobs,
    List<JobListItem>? recentJobs,
    Map<JobRunId, JobDetail>? details,
  }) : activeJobs = activeJobs ?? [],
       recentJobs = recentJobs ?? [],
       details = details ?? {};

  List<JobListItem> activeJobs;
  List<JobListItem> recentJobs;
  Map<JobRunId, JobDetail> details;
  Object? listFailure;
  Object? detailFailure;
  CancelJobResult Function(JobRunId jobRunId)? onCancel;

  int activeCalls = 0;
  int recentCalls = 0;
  int getCalls = 0;
  int cancelCalls = 0;

  @override
  Future<JobSummaryPage> listActiveJobs() async {
    activeCalls++;
    final failure = listFailure;
    if (failure != null) {
      listFailure = null;
      throw failure;
    }
    return JobSummaryPage(items: activeJobs, totalCount: activeJobs.length);
  }

  @override
  Future<JobSummaryPage> listRecentTerminalJobs({
    required int offset,
    required int pageSize,
  }) async {
    recentCalls++;
    final failure = listFailure;
    if (failure != null) {
      listFailure = null;
      throw failure;
    }
    final page = recentJobs.skip(offset).take(pageSize).toList();
    return JobSummaryPage(
      items: page,
      totalCount: recentJobs.length,
      nextOffset: offset + page.length < recentJobs.length
          ? offset + page.length
          : null,
    );
  }

  @override
  Future<JobDetail> getJob(JobRunId jobRunId) async {
    getCalls++;
    final failure = detailFailure;
    if (failure != null) {
      detailFailure = null;
      throw failure;
    }
    return details[jobRunId] ?? (throw jobNotFoundFailure());
  }

  @override
  Future<CancelJobResult> cancelJob(JobRunId jobRunId) async {
    cancelCalls++;
    final handler = onCancel;
    if (handler != null) return handler(jobRunId);
    return CancelJobResult.cancellationRequested;
  }

  @override
  Future<ActiveJobSummary> getActiveJobSummary() async {
    final active = await listActiveJobs();
    return ActiveJobSummary(
      activeCount: active.items.length,
      soleActiveJobRunId: active.items.length == 1
          ? active.items.single.jobRunId
          : null,
    );
  }
}

JobRunId jobRunId(String value) => JobRunId(value);

JobListItem jobItem({
  String id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  JobLifecycleState state = JobLifecycleState.running,
  bool cancellationRequested = false,
}) => JobListItem(
  jobRunId: JobRunId(id),
  operationType: 'library_scan',
  lifecycleState: state,
  createdAtMs: 1,
  cancellationRequested: cancellationRequested,
);

JobDetail jobDetail({
  String id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  JobLifecycleState state = JobLifecycleState.running,
  bool cancellationRequested = false,
}) => JobDetail(
  job: JobRunProjection(
    jobRunId: JobRunId(id),
    operationType: 'library_scan',
    lifecycleState: state,
    createdAtMs: 1,
    cancellationRequested: cancellationRequested,
    controls: JobControlAvailability(
      canCancel: state == JobLifecycleState.running && !cancellationRequested,
      canRetry: false,
    ),
  ),
  operationDetail: OperationDetail.libraryScan(
    LibraryScanJobDetail(
      requestedRoots: const [],
      admittedRoots: const [],
      exclusions: const [],
      scanRuns: const [],
      progress: ScanProgressFacts(
        rootsRequested: 1,
        rootsAdmitted: 1,
        rootsTerminal: 0,
        entriesCommitted: 0,
      ),
    ),
  ),
);

ApplicationFailure jobNotFoundFailure() => ApplicationFailure(
  ClientApplicationError(
    code: const ErrorCode('ARGUS.V1.JOBS.JOB_RUN_NOT_FOUND'),
    category: ErrorCategory.operation,
    severity: ApplicationSeverity.warning,
    recoverability: Recoverability.userAction,
    retryPolicy: RetryPolicy.never,
    messageKey: const MessageKey('errors.jobs.job_run_not_found'),
    traceId: const TraceId('11111111111111111111111111111111'),
    safeContext: const [],
  ),
);
