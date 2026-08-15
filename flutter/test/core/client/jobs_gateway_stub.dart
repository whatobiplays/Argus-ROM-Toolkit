import 'package:argus/core/client/client.dart';

/// Test-only default Jobs gateway surface for unrelated client fakes.
///
/// Fakes that exercise runtime/appearance/sources behavior but never Jobs can
/// mix this in to satisfy the extended gateway contract without duplicating
/// stubs. Any test that actually calls a Jobs operation must provide its own
/// focused fake.
mixin JobsGatewayStub implements JobsGateway {
  @override
  Future<JobSummaryPage> listActiveJobs() async =>
      JobSummaryPage(items: const [], totalCount: 0);

  @override
  Future<JobSummaryPage> listRecentTerminalJobs({
    required int offset,
    required int pageSize,
  }) async => JobSummaryPage(items: const [], totalCount: 0);

  @override
  Future<JobDetail> getJob(JobRunId jobRunId) async =>
      throw const TransportFailure('Jobs stub is not focused');

  @override
  Future<CancelJobResult> cancelJob(JobRunId jobRunId) async =>
      throw const TransportFailure('Jobs stub is not focused');

  @override
  Future<RetryJobResult> retryJob(JobRunId jobRunId) async =>
      throw const TransportFailure('Jobs stub is not focused');

  @override
  Future<LibraryRootScanAdmission?> getRootScanAdmission(
    LibraryRootId libraryRootId,
  ) async => throw const TransportFailure('Jobs stub is not focused');
}
