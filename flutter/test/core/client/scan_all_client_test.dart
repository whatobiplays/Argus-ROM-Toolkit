import 'package:argus/core/client/client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'jobs_gateway_stub.dart';
import 'sources_gateway_stub.dart';

const String _jobIdHex = '01010101010101010101010101010101';
const String _rootIdHex = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

final class _ScanAllFakeGateway
    with SourcesGatewayStub, JobsGatewayStub
    implements ArgusClientGateway {
  StartLibraryScanAllResult? scanAllResult;
  LibraryScanAllRequestResolution? resolution;
  Object? scanAllFailure;
  Object? resolveFailure;
  final List<String> scanAllRequestIdentities = [];
  final List<String> resolveRequestIdentities = [];

  @override
  Future<StartLibraryScanAllResult> startLibraryScanAll(
    ScanAllRequestIdentity requestIdentity,
  ) async {
    scanAllRequestIdentities.add(requestIdentity.value);
    if (scanAllFailure case final Object failure) throw failure;
    return scanAllResult ??
        StartLibraryScanAllResult.nothingEligible(exclusions: const []);
  }

  @override
  Future<LibraryScanAllRequestResolution> resolveScanAllRequest(
    ScanAllRequestIdentity requestIdentity,
  ) async {
    resolveRequestIdentities.add(requestIdentity.value);
    if (resolveFailure case final Object failure) throw failure;
    return resolution ??
        const LibraryScanAllRequestResolution.nothingAdmitted();
  }

  @override
  Future<void> closeEventConnection() async {}

  @override
  Future<void> generalShutdown() async {}

  @override
  Future<RuntimeState> getRuntimeState() async => RuntimeState.ready(
    runtimeInstanceId: const RuntimeInstanceId(_rootIdHex),
  );

  @override
  Future<RuntimeState> initialize() async => RuntimeState.ready(
    runtimeInstanceId: const RuntimeInstanceId(_rootIdHex),
  );

  @override
  Future<AppearanceSettings> getAppearanceSettings() async =>
      const AppearanceSettings(themeMode: ThemeMode.system);

  @override
  Future<void> updateAppearanceSettings(AppearanceSettings settings) async {}

  @override
  Future<DiagnosticsExport> exportStartupDiagnostics(
    RuntimeInstanceId expectedRuntimeInstanceId,
    String destination,
  ) async {
    return const DiagnosticsExport(
      outcome: DiagnosticsExportOutcome.created,
      destinationClassification: 'test',
    );
  }

  @override
  Future<TechnicalDetails> startupTechnicalDetails(
    RuntimeInstanceId expectedRuntimeInstanceId,
  ) async {
    return const TechnicalDetails(text: 'details');
  }

  @override
  Future<void> openStartupDataDirectory(
    RuntimeInstanceId expectedRuntimeInstanceId,
  ) async {}

  @override
  Future<RuntimeState> retryStartup(
    RuntimeInstanceId expectedRuntimeInstanceId,
  ) async {
    return RuntimeState.ready(
      runtimeInstanceId: const RuntimeInstanceId(_rootIdHex),
    );
  }

  @override
  Future<RuntimeState> resetAppearanceSettings(
    RuntimeInstanceId expectedRuntimeInstanceId,
  ) async {
    return RuntimeState.ready(
      runtimeInstanceId: const RuntimeInstanceId(_rootIdHex),
    );
  }

  @override
  Future<RuntimeState> exitFailedRuntime(
    RuntimeInstanceId expectedRuntimeInstanceId,
  ) async {
    return RuntimeState.stopped(
      runtimeInstanceId: const RuntimeInstanceId(_rootIdHex),
    );
  }

  @override
  Future<EventBindResult> subscribeEvents(RuntimeInstanceId generation) async {
    return EventBindResult(
      stream: const Stream<RuntimeEvent>.empty(),
      nativeAttached: false,
    );
  }
}

void main() {
  test(
    'SourcesApi delegates Scan All with the durable request identity',
    () async {
      final gateway = _ScanAllFakeGateway();
      final client = ArgusClient(gateway: gateway);
      const identity = ScanAllRequestIdentity('request-1');
      final admitted = StartLibraryScanAllResult.admitted(
        handle: const OperationHandle(
          jobRunId: JobRunId(_jobIdHex),
          operationType: 'library_scan',
        ),
        admittedRoots: const [LibraryRootId(_rootIdHex)],
        exclusions: const [],
      );
      gateway.scanAllResult = admitted;

      final result = await client.sources.startLibraryScanAll(identity);

      expect(gateway.scanAllRequestIdentities, ['request-1']);
      expect(result, isA<StartLibraryScanAllResultAdmitted>());
      expect(
        (result as StartLibraryScanAllResultAdmitted).handle.jobRunId.value,
        _jobIdHex,
      );
    },
  );

  test(
    'JobsApi reconciles a Scan All request identity authoritatively',
    () async {
      final gateway = _ScanAllFakeGateway();
      final client = ArgusClient(gateway: gateway);
      const identity = ScanAllRequestIdentity('request-2');
      gateway.resolution =
          const LibraryScanAllRequestResolution.nothingAdmitted();

      final result = await client.jobs.resolveScanAllRequest(identity);

      expect(gateway.resolveRequestIdentities, ['request-2']);
      expect(result, isA<LibraryScanAllRequestResolutionNothingAdmitted>());
    },
  );

  test(
    'Scan All transport failure surfaces as a typed client failure',
    () async {
      final gateway = _ScanAllFakeGateway()
        ..scanAllFailure = const TransportFailure('ambiguous');
      final client = ArgusClient(gateway: gateway);

      await expectLater(
        client.sources.startLibraryScanAll(
          const ScanAllRequestIdentity('request-3'),
        ),
        throwsA(isA<TransportFailure>()),
      );
    },
  );
}
