import 'package:argus/core/client/client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'jobs_gateway_stub.dart';

const String _entryIdHex = '11111111111111111111111111111111';
const String _parentIdHex = '22222222222222222222222222222222';
const String _rootIdHex = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _traceIdHex = '11111111111111111111111111111111';

void main() {
  test('SourceEntryId validates canonical lowercase hex identities', () {
    expect(
      const SourceEntryId('0123456789abcdef0123456789abcdef').isValid,
      isTrue,
    );
    expect(
      const SourceEntryId('00000000000000000000000000000000').isValid,
      isFalse,
    );
    expect(const SourceEntryId('short').isValid, isFalse);
    expect(SourceEntryId.tryParse(_entryIdHex), isNotNull);
    expect(SourceEntryId.tryParse('bad'), isNull);
  });

  test('source-entry wire mappings are closed and typed', () {
    expect(SourceEntryKind.fromWire('directory'), SourceEntryKind.directory);
    expect(SourceEntryKind.fromWire('link_like'), SourceEntryKind.linkLike);
    expect(
      () => SourceEntryKind.fromWire('archive'),
      throwsA(
        isA<TransportFailure>().having(
          (failure) => failure.kind,
          'kind',
          TransportFailureKind.contractMismatch,
        ),
      ),
    );
    expect(
      SourceEntryClassification.fromWire('content_candidate'),
      SourceEntryClassification.contentCandidate,
    );
    expect(
      SourceEntryClassification.fromWire('ignored'),
      SourceEntryClassification.ignored,
    );
  });

  test(
    'SourcesApi delegates hierarchy reads and preserves opaque cursors',
    () async {
      final gateway = _HierarchyFakeGateway();
      final client = ArgusClient(gateway: gateway);
      const cursor = 'v1:1700000000:11111111111111111111111111111111';

      final page = await client.sources.listSourceEntryChildren(
        libraryRootId: const LibraryRootId(_rootIdHex),
        parentSourceEntryId: const SourceEntryId(_parentIdHex),
        cursor: cursor,
        pageSize: 25,
      );

      expect(gateway.lastRootId, const LibraryRootId(_rootIdHex));
      expect(gateway.lastParent, const SourceEntryId(_parentIdHex));
      expect(
        gateway.lastCursor,
        cursor,
        reason: 'cursor stays byte-for-byte opaque',
      );
      expect(gateway.lastPageSize, 25);
      expect(page.items.single.displayName, 'a.bin');
      expect(
        page.items.single.parentSourceEntryId,
        const SourceEntryId(_parentIdHex),
      );
      expect(page.nextCursor, 'next-token');

      final detail = await client.sources.getSourceEntry(
        const SourceEntryId(_entryIdHex),
      );
      expect(detail.kind, SourceEntryKind.file);
      expect(detail.classification, SourceEntryClassification.unknown);
      await client.dispose();
    },
  );

  test('SourcesApi surfaces application failures distinctly', () async {
    final gateway = _HierarchyFakeGateway()
      ..failNextGet = ApplicationFailure(
        ClientApplicationError(
          code: const ErrorCode(
            'ARGUS.V1.CONFIGURATION.SOURCE_ENTRY_NOT_FOUND',
          ),
          category: ErrorCategory.configuration,
          severity: ApplicationSeverity.error,
          recoverability: Recoverability.userAction,
          retryPolicy: RetryPolicy.never,
          messageKey: const MessageKey(
            'errors.configuration.source_entry_not_found',
          ),
          traceId: const TraceId(_traceIdHex),
          safeContext: const [],
        ),
      );
    final client = ArgusClient(gateway: gateway);

    await expectLater(
      client.sources.getSourceEntry(const SourceEntryId(_entryIdHex)),
      throwsA(
        isA<ApplicationFailure>().having(
          (failure) => failure.error.code.value,
          'code',
          'ARGUS.V1.CONFIGURATION.SOURCE_ENTRY_NOT_FOUND',
        ),
      ),
    );
    await client.dispose();
  });
}

final class _HierarchyFakeGateway
    with JobsGatewayStub
    implements ArgusClientGateway {
  ApplicationFailure? failNextGet;
  LibraryRootId? lastRootId;
  SourceEntryId? lastParent;
  String? lastCursor;
  int? lastPageSize;

  @override
  Future<SourceEntryChildrenPage> listSourceEntryChildren({
    required LibraryRootId libraryRootId,
    SourceEntryId? parentSourceEntryId,
    String? cursor,
    required int pageSize,
  }) async {
    lastRootId = libraryRootId;
    lastParent = parentSourceEntryId;
    lastCursor = cursor;
    lastPageSize = pageSize;
    return SourceEntryChildrenPage(
      items: [
        SourceEntry(
          sourceEntryId: const SourceEntryId(_entryIdHex),
          parentSourceEntryId: parentSourceEntryId,
          displayName: 'a.bin',
          displayLocation: 'a.bin',
          kind: SourceEntryKind.file,
          classification: SourceEntryClassification.unknown,
        ),
      ],
      nextCursor: 'next-token',
    );
  }

  @override
  Future<SourceEntryDetail> getSourceEntry(SourceEntryId sourceEntryId) async {
    final failure = failNextGet;
    if (failure != null) {
      failNextGet = null;
      throw failure;
    }
    return SourceEntryDetail(
      sourceEntryId: sourceEntryId,
      parentSourceEntryId: null,
      displayName: 'a.bin',
      displayLocation: 'a.bin',
      kind: SourceEntryKind.file,
      classification: SourceEntryClassification.unknown,
    );
  }

  @override
  Future<LibraryRoot> getLibraryRoot(LibraryRootId libraryRootId) async =>
      throw const TransportFailure('hierarchy fake is not focused on roots');

  @override
  Future<LibraryRootPage> listLibraryRoots({
    required int offset,
    required int pageSize,
  }) async =>
      throw const TransportFailure('hierarchy fake is not focused on roots');

  @override
  Future<AddLocalLibraryRootResult> addLocalLibraryRoot(
    LocalFilesystemRootSelection selection,
  ) async =>
      throw const TransportFailure('hierarchy fake is not focused on roots');

  @override
  Future<AddLocalLibraryRootAndScanResult> addLocalLibraryRootAndScan(
    LocalFilesystemRootSelection selection,
  ) async =>
      throw const TransportFailure('hierarchy fake is not focused on roots');

  @override
  Future<RemoveLibraryRootResult> removeLibraryRoot(
    LibraryRootId libraryRootId,
  ) async =>
      throw const TransportFailure('hierarchy fake is not focused on roots');

  @override
  Future<StartLibraryScanResult> startLibraryScan(
    LibraryRootId libraryRootId,
  ) async =>
      throw const TransportFailure('hierarchy fake is not focused on roots');

  @override
  Future<StartLibraryScanAllResult> startLibraryScanAll(
    ScanAllRequestIdentity requestIdentity,
  ) async =>
      throw const TransportFailure('hierarchy fake is not focused on roots');

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
  ) async => const DiagnosticsExport(
    outcome: DiagnosticsExportOutcome.created,
    destinationClassification: 'test',
  );

  @override
  Future<TechnicalDetails> startupTechnicalDetails(
    RuntimeInstanceId expectedRuntimeInstanceId,
  ) async => const TechnicalDetails(text: 'details');

  @override
  Future<void> openStartupDataDirectory(
    RuntimeInstanceId expectedRuntimeInstanceId,
  ) async {}

  @override
  Future<RuntimeState> retryStartup(
    RuntimeInstanceId expectedRuntimeInstanceId,
  ) async => RuntimeState.ready(
    runtimeInstanceId: const RuntimeInstanceId(_rootIdHex),
  );

  @override
  Future<RuntimeState> resetAppearanceSettings(
    RuntimeInstanceId expectedRuntimeInstanceId,
  ) async => RuntimeState.ready(
    runtimeInstanceId: const RuntimeInstanceId(_rootIdHex),
  );

  @override
  Future<RuntimeState> exitFailedRuntime(
    RuntimeInstanceId expectedRuntimeInstanceId,
  ) async => const RuntimeState.stopped(
    runtimeInstanceId: RuntimeInstanceId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
  );

  @override
  Future<EventBindResult> subscribeEvents(RuntimeInstanceId generation) async {
    return EventBindResult(
      stream: const Stream<RuntimeEvent>.empty(),
      nativeAttached: false,
    );
  }
}
