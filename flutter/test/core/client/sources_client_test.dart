import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'jobs_gateway_stub.dart';

const String _rootIdHex = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _traceIdHex = '11111111111111111111111111111111';

void main() {
  test('LibraryRootId validates canonical lowercase hex identities', () {
    const valid = LibraryRootId('0123456789abcdef0123456789abcdef');
    expect(valid.isValid, isTrue);
    expect(
      const LibraryRootId('00000000000000000000000000000000').isValid,
      isFalse,
    );
    expect(
      const LibraryRootId('0123456789abcdef0123456789abcdeZ').isValid,
      isFalse,
    );
    expect(const LibraryRootId('short').isValid, isFalse);
  });

  test('enum wire mappings are closed and typed', () {
    expect(
      LibraryRootAvailability.fromWire('available'),
      LibraryRootAvailability.available,
    );
    expect(
      () => LibraryRootAvailability.fromWire('unknown-value'),
      throwsA(
        isA<TransportFailure>().having(
          (failure) => failure.kind,
          'kind',
          TransportFailureKind.contractMismatch,
        ),
      ),
    );
    expect(RootRelationship.fromWire('ancestor'), RootRelationship.ancestor);
    expect(
      LibraryRootLastScanStatus.fromWire('abandoned'),
      LibraryRootLastScanStatus.abandoned,
    );
  });

  test('SourcesApi delegates every focused operation to the gateway', () async {
    final gateway = _SourcesFakeGateway();
    final client = ArgusClient(gateway: gateway);

    final page = await client.sources.listLibraryRoots(offset: 0, pageSize: 25);
    expect(page.items.single.id.value, _rootIdHex);
    expect(page.totalCount, 1);

    final root = await client.sources.getLibraryRoot(
      const LibraryRootId(_rootIdHex),
    );
    expect(root.displayName, 'Games');
    expect(root.availability, LibraryRootAvailability.available);
    expect(root.lastScan, isNull);
    expect(root.activeScan, isNull);

    final added = await client.sources.addLocalLibraryRoot(
      const LocalFilesystemRootSelection('/tmp/games'),
    );
    expect(
      added,
      AddLocalLibraryRootResult.added(
        LibraryRoot(
          id: const LibraryRootId(_rootIdHex),
          displayName: 'Games',
          safeLocationPresentation: '/tmp/games',
          availability: LibraryRootAvailability.available,
        ),
      ),
    );

    final removed = await client.sources.removeLibraryRoot(
      const LibraryRootId(_rootIdHex),
    );
    expect(removed, isA<RemoveLibraryRootResultRemoved>());
    await client.dispose();
  });

  test('SourcesApi surfaces application failures distinctly', () async {
    final gateway = _SourcesFakeGateway()
      ..failNextGet = ApplicationFailure(
        ClientApplicationError(
          code: const ErrorCode(
            'ARGUS.V1.CONFIGURATION.LIBRARY_ROOT_NOT_FOUND',
          ),
          category: ErrorCategory.configuration,
          severity: ApplicationSeverity.error,
          recoverability: Recoverability.userAction,
          retryPolicy: RetryPolicy.never,
          messageKey: const MessageKey(
            'errors.configuration.library_root_not_found',
          ),
          traceId: const TraceId(_traceIdHex),
          safeContext: const [],
        ),
      );
    final client = ArgusClient(gateway: gateway);

    await expectLater(
      client.sources.getLibraryRoot(const LibraryRootId(_rootIdHex)),
      throwsA(
        isA<ApplicationFailure>().having(
          (failure) => failure.error.code.value,
          'code',
          'ARGUS.V1.CONFIGURATION.LIBRARY_ROOT_NOT_FOUND',
        ),
      ),
    );
    await client.dispose();
  });
}

final class _SourcesFakeGateway
    with JobsGatewayStub
    implements ArgusClientGateway {
  ApplicationFailure? failNextGet;

  @override
  Future<LibraryRoot> getLibraryRoot(LibraryRootId libraryRootId) async {
    final failure = failNextGet;
    if (failure != null) {
      failNextGet = null;
      throw failure;
    }
    return _root();
  }

  @override
  Future<LibraryRootPage> listLibraryRoots({
    required int offset,
    required int pageSize,
  }) async {
    return LibraryRootPage(
      items: [_root()],
      offset: offset,
      pageSize: pageSize,
      totalCount: 1,
    );
  }

  @override
  Future<AddLocalLibraryRootResult> addLocalLibraryRoot(
    LocalFilesystemRootSelection selection,
  ) async {
    return AddLocalLibraryRootResult.added(
      LibraryRoot(
        id: const LibraryRootId(_rootIdHex),
        displayName: 'Games',
        safeLocationPresentation: selection.selectedFolderPath,
        availability: LibraryRootAvailability.available,
      ),
    );
  }

  @override
  Future<RemoveLibraryRootResult> removeLibraryRoot(
    LibraryRootId libraryRootId,
  ) async {
    return const RemoveLibraryRootResult.removed();
  }

  @override
  Future<StartLibraryScanResult> startLibraryScan(
    LibraryRootId libraryRootId,
  ) async => throw const TransportFailure('Sources stub is not focused');

  LibraryRoot _root() => LibraryRoot(
    id: const LibraryRootId(_rootIdHex),
    displayName: 'Games',
    safeLocationPresentation: '/tmp/games',
    availability: LibraryRootAvailability.available,
  );

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
