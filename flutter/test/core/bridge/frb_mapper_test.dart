import 'package:argus/core/bridge/generated/lib.dart' as dto;
import 'package:argus/core/bridge/src/frb_argus_client_gateway.dart';
import 'package:argus/core/client/client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('library root DTO maps projections without locator leakage', () {
    final root = libraryRootFromDto(
      const dto.LibraryRootDto(
        libraryRootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        displayName: 'Games',
        safeLocationPresentation: '/library/Games',
        availability: dto.LibraryRootAvailabilityDto.available,
        lastScan: null,
        activeScan: null,
      ),
    );

    expect(root.id.value, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    expect(root.displayName, 'Games');
    expect(root.safeLocationPresentation, '/library/Games');
    expect(root.availability, LibraryRootAvailability.available);
    expect(root.lastScan, isNull);
    expect(root.activeScan, isNull);
  });

  test('library root DTO rejects malformed identity as contract mismatch', () {
    expect(
      () => libraryRootFromDto(
        const dto.LibraryRootDto(
          libraryRootId: 'not-an-id',
          displayName: 'Games',
          safeLocationPresentation: '/library/Games',
          availability: dto.LibraryRootAvailabilityDto.unknown,
        ),
      ),
      throwsA(
        isA<TransportFailure>().having(
          (failure) => failure.kind,
          'kind',
          TransportFailureKind.contractMismatch,
        ),
      ),
    );
  });

  test('library root page DTO maps bounded paging facts', () {
    final page = libraryRootPageFromDto(
      const dto.LibraryRootPageDto(
        items: [
          dto.LibraryRootDto(
            libraryRootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            displayName: 'Games',
            safeLocationPresentation: '/library/Games',
            availability: dto.LibraryRootAvailabilityDto.available,
          ),
        ],
        offset: 0,
        pageSize: 10,
        totalCount: 1,
      ),
    );

    expect(page.items.single.displayName, 'Games');
    expect(page.offset, 0);
    expect(page.pageSize, 10);
    expect(page.totalCount, 1);
  });

  test('add result DTO maps every typed outcome', () {
    final added = addLocalLibraryRootResultFromDto(
      dto.AddLocalLibraryRootResultDto.added(
        const dto.LibraryRootDto(
          libraryRootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          displayName: 'Games',
          safeLocationPresentation: '/library/Games',
          availability: dto.LibraryRootAvailabilityDto.available,
        ),
      ),
    );
    expect(added, isA<AddLocalLibraryRootResultAdded>());

    final already = addLocalLibraryRootResultFromDto(
      dto.AddLocalLibraryRootResultDto.alreadyConfigured(
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      ),
    );
    expect(
      already,
      AddLocalLibraryRootResult.alreadyConfigured(
        const LibraryRootId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
      ),
    );

    final overlap = addLocalLibraryRootResultFromDto(
      dto.AddLocalLibraryRootResultDto.overlapsExisting(
        'cccccccccccccccccccccccccccccccc',
        dto.RootRelationshipDto.ancestor,
      ),
    );
    expect(
      overlap,
      AddLocalLibraryRootResult.overlapsExisting(
        existingLibraryRootId: const LibraryRootId(
          'cccccccccccccccccccccccccccccccc',
        ),
        relationship: RootRelationship.ancestor,
      ),
    );
  });

  test('remove result DTO maps the slice outcome', () {
    expect(
      removeLibraryRootResultFromDto(dto.RemoveLibraryRootResultDto.removed()),
      const RemoveLibraryRootResult.removed(),
    );
  });

  test('sources event payloads map with bounded identity only', () {
    final roots = runtimeEventFromDto(
      dto.RuntimeEventDto(
        runtimeInstanceId: '1234567890abcdef1234567890abcdef',
        sequence: BigInt.one,
        occurredAtMs: BigInt.from(100),
        payload: const dto.RuntimeEventPayloadDto.libraryRootsChanged(),
      ),
    );
    expect(roots.payload, isA<RuntimeEventPayloadLibraryRootsChanged>());

    final root = runtimeEventFromDto(
      dto.RuntimeEventDto(
        runtimeInstanceId: '1234567890abcdef1234567890abcdef',
        sequence: BigInt.two,
        occurredAtMs: BigInt.from(101),
        payload: const dto.RuntimeEventPayloadDto.libraryRootChanged(
          libraryRootId: 'dddddddddddddddddddddddddddddddd',
        ),
      ),
    );
    expect(
      root.payload,
      RuntimeEventPayload.libraryRootChanged(
        libraryRootId: const LibraryRootId('dddddddddddddddddddddddddddddddd'),
      ),
    );
  });

  test('invalid runtime identity fails through TransportFailure', () {
    expect(
      () => runtimeStateFromDto(
        const dto.RuntimeStateDto(
          runtimeInstanceId: '00000000000000000000000000000000',
          lifecycleState: dto.RuntimeLifecycleDto.ready,
          startupPhase: null,
          startupFailure: null,
        ),
      ),
      throwsA(
        isA<TransportFailure>().having(
          (failure) => failure.kind,
          'kind',
          TransportFailureKind.contractMismatch,
        ),
      ),
    );
  });

  test('malformed application error trace fails as contract mismatch', () {
    expect(
      () => applicationErrorFromDto(
        const dto.ApplicationErrorDto(
          code: 'ARGUS.V1.RUNTIME.STALE_INSTANCE',
          category: 'runtime',
          severity: 'Warning',
          recoverability: 'UserAction',
          retryPolicy: 'Never',
          messageKey: 'errors.runtime.stale_instance',
          traceId: 'not-a-trace',
          safeContext: [],
        ),
      ),
      throwsA(
        isA<TransportFailure>().having(
          (failure) => failure.kind,
          'kind',
          TransportFailureKind.contractMismatch,
        ),
      ),
    );
  });

  test('malformed application error code fails as contract mismatch', () {
    expect(
      () => applicationErrorFromDto(
        const dto.ApplicationErrorDto(
          code: 'not-a-code',
          category: 'runtime',
          severity: 'Warning',
          recoverability: 'UserAction',
          retryPolicy: 'Never',
          messageKey: 'errors.runtime.stale_instance',
          traceId: '01010101010101010101010101010101',
          safeContext: [],
        ),
      ),
      throwsA(
        isA<TransportFailure>().having(
          (failure) => failure.kind,
          'kind',
          TransportFailureKind.contractMismatch,
        ),
      ),
    );
  });

  test(
    'native-library initialization failure maps to bridgeUnavailable',
    () async {
      final gateway = FrbArgusClientGateway(
        initializeNative: () async => throw StateError('load failed'),
      );
      final client = ArgusClient(gateway: gateway);

      await expectLater(
        client.initialize(),
        throwsA(
          isA<TransportFailure>().having(
            (failure) => failure.kind,
            'kind',
            TransportFailureKind.bridgeUnavailable,
          ),
        ),
      );
    },
  );

  test(
    'native event stream transport failure maps to communicationFailed',
    () async {
      final gateway = FrbArgusClientGateway(
        initializeNative: () async {},
        eventStreamFactory: () => Stream<dto.RuntimeEventDto>.error(
          dto.BridgeTransportError.eventStreamClosed,
        ),
      );

      final bind = await gateway.subscribeEvents(RuntimeInstanceId('a' * 32));
      await expectLater(
        bind.stream,
        emitsError(
          isA<TransportFailure>().having(
            (failure) => failure.kind,
            'kind',
            TransportFailureKind.communicationFailed,
          ),
        ),
      );
    },
  );

  test('startup failure state requires matching authoritative context', () {
    expect(
      () => runtimeStateFromDto(
        const dto.RuntimeStateDto(
          runtimeInstanceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          lifecycleState: dto.RuntimeLifecycleDto.startupFailed,
          startupPhase: dto.StartupPhaseDto.persistenceInitialization,
          startupFailure: null,
        ),
      ),
      throwsA(
        isA<TransportFailure>().having(
          (failure) => failure.kind,
          'kind',
          TransportFailureKind.contractMismatch,
        ),
      ),
    );
  });

  test('state-changed notification carries lifecycle only', () {
    final mapped = runtimeEventFromDto(
      dto.RuntimeEventDto(
        runtimeInstanceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        sequence: BigInt.one,
        occurredAtMs: BigInt.one,
        payload: dto.RuntimeEventPayloadDto.runtimeStateChanged(
          lifecycle: dto.RuntimeLifecycleDto.ready,
        ),
      ),
    );

    expect(mapped.payload, isA<RuntimeEventPayloadRuntimeStateChanged>());
    final payload = mapped.payload as RuntimeEventPayloadRuntimeStateChanged;
    expect(payload.lifecycle, RuntimeLifecycle.ready);
  });

  test('application error maps field-for-field', () {
    final mapped = applicationErrorFromDto(
      const dto.ApplicationErrorDto(
        code: 'ARGUS.V1.RUNTIME.STALE_INSTANCE',
        category: 'runtime',
        severity: 'Error',
        recoverability: 'UserAction',
        retryPolicy: 'Never',
        messageKey: 'errors.runtime.stale_instance',
        traceId: '07070707070707070707070707070707',
        safeContext: [
          dto.SafeContextEntryDto(field: 'failure_role', value: 'primary'),
        ],
      ),
    );

    expect(mapped.code, const ErrorCode('ARGUS.V1.RUNTIME.STALE_INSTANCE'));
    expect(mapped.category, ErrorCategory.runtime);
    expect(mapped.severity, ApplicationSeverity.error);
    expect(mapped.recoverability, Recoverability.userAction);
    expect(mapped.retryPolicy, RetryPolicy.never);
    expect(
      mapped.messageKey,
      const MessageKey('errors.runtime.stale_instance'),
    );
    expect(mapped.traceId, const TraceId('07070707070707070707070707070707'));
    expect(mapped.safeContext.single.field, SafeContextField.failureRole);
    expect(
      mapped.safeContext.single.value,
      const SafeContextValue.string('primary'),
    );
  });

  test('startup failure state maps authoritative context', () {
    final mapped = runtimeStateFromDto(
      const dto.RuntimeStateDto(
        runtimeInstanceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        lifecycleState: dto.RuntimeLifecycleDto.startupFailed,
        startupPhase: dto.StartupPhaseDto.settingsInitialization,
        startupFailure: dto.StartupFailureDto(
          phase: dto.StartupPhaseDto.settingsInitialization,
          error: dto.ApplicationErrorDto(
            code: 'ARGUS.V1.CONFIGURATION.PERSISTED_SETTINGS_INVALID',
            category: 'configuration',
            severity: 'Error',
            recoverability: 'UserAction',
            retryPolicy: 'UserInitiated',
            messageKey: 'errors.configuration.persisted_settings_invalid',
            traceId: '08080808080808080808080808080808',
            safeContext: [],
          ),
          recoveryActions: [
            dto.RecoveryActionDto(kind: dto.RecoveryActionKindDto.retryStartup),
          ],
        ),
      ),
    );

    expect(mapped, isA<RuntimeStateStartupFailed>());
    final failed = mapped as RuntimeStateStartupFailed;
    expect(failed.failure.phase, StartupPhase.settingsInitialization);
    expect(
      failed.failure.recoveryActions.single.kind,
      RecoveryActionKind.retryStartup,
    );
  });

  test('runtime event sequence and gap metadata survive mapping', () {
    final mapped = runtimeEventFromDto(
      dto.RuntimeEventDto(
        runtimeInstanceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        sequence: BigInt.from(7),
        occurredAtMs: BigInt.from(1234),
        payload: const dto.RuntimeEventPayloadDto.appearanceSettingsChanged(),
      ),
    );

    expect(mapped.runtimeInstanceId.value, 'a' * 32);
    expect(mapped.sequence, BigInt.from(7));
    expect(mapped.occurredAtMs, BigInt.from(1234));
    expect(mapped.payload, isA<RuntimeEventPayloadAppearanceSettingsChanged>());
  });

  test('bounded safe-context values map to typed scalars', () {
    final mapped = safeContextEntryFromDto(
      const dto.SafeContextEntryDto(field: 'migration_count', value: '3'),
    );

    expect(mapped.field, SafeContextField.migrationCount);
    expect(mapped.value, const SafeContextValue.integer(3));
  });

  test('unknown safe-context fields fail as contract mismatches', () {
    expect(
      () => safeContextEntryFromDto(
        const dto.SafeContextEntryDto(field: 'secret_field', value: 'x'),
      ),
      throwsA(
        isA<TransportFailure>().having(
          (failure) => failure.kind,
          'kind',
          TransportFailureKind.contractMismatch,
        ),
      ),
    );
  });

  test('scan admission and cancel results map with typed identities', () {
    final admitted = startLibraryScanResultFromDto(
      dto.StartLibraryScanResultDto_Admitted(
        dto.OperationHandleDto(
          jobRunId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          operationType: 'library_scan',
        ),
      ),
    );
    expect(
      admitted,
      isA<StartLibraryScanResultAdmitted>().having(
        (result) => result.handle.jobRunId,
        'jobRunId',
        const JobRunId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
      ),
    );

    final already = startLibraryScanResultFromDto(
      dto.StartLibraryScanResultDto_AlreadyScanning(
        libraryRootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        activeJobRunId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        activeScanRunId: 'cccccccccccccccccccccccccccccccc',
      ),
    );
    expect(already, isA<StartLibraryScanResultAlreadyScanning>());

    expect(
      cancelJobResultFromDto(dto.CancelJobResultDto.cancellationRequested),
      CancelJobResult.cancellationRequested,
    );
  });

  test('job detail and progress map with lifecycle and scan facts', () {
    final detail = jobDetailFromDto(
      dto.JobDetailDto(
        job: dto.JobRunDto(
          jobRunId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          operationType: 'library_scan',
          state: dto.JobRunStateDto.running,
          phase: 'discovering',
          completedUnits: BigInt.from(3),
          totalUnits: null,
          statusKey: 'library_scan.discovering',
          createdAtMs: 1,
          cancellationRequested: false,
          controls: const dto.JobControlAvailabilityDto(
            canCancel: true,
            canRetry: false,
          ),
          boundedTerminalFailure: null,
        ),
        operationDetail: dto.OperationDetailDto_LibraryScan(
          dto.LibraryScanJobDetailDto(
            requestedRoots: const [],
            admittedRoots: const [],
            exclusions: const [],
            scanRuns: const [],
            progress: dto.ScanProgressFactsDto(
              rootsRequested: 1,
              rootsAdmitted: 1,
              rootsTerminal: 0,
              entriesCommitted: BigInt.from(3),
            ),
            retrySourceJobRunId: null,
            retrySuccessorJobRunId: null,
          ),
        ),
      ),
    );

    expect(detail.job.lifecycleState, JobLifecycleState.running);
    expect(detail.job.completedUnits, 3);
    expect(detail.job.controls.canCancel, isTrue);
    final scanDetail = detail.operationDetail as OperationDetailLibraryScan;
    expect(scanDetail.detail.progress.entriesCommitted, 3);
  });

  test('job and source-entry event payloads map with bounded identity', () {
    final jobState = runtimeEventFromDto(
      dto.RuntimeEventDto(
        runtimeInstanceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        sequence: BigInt.from(1),
        occurredAtMs: BigInt.from(1),
        payload: const dto.RuntimeEventPayloadDto.jobStateChanged(
          jobRunId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        ),
      ),
    );
    expect(jobState.payload, isA<RuntimeEventPayloadJobStateChanged>());

    final entries = runtimeEventFromDto(
      dto.RuntimeEventDto(
        runtimeInstanceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        sequence: BigInt.from(2),
        occurredAtMs: BigInt.from(2),
        payload: dto.RuntimeEventPayloadDto.sourceEntriesChanged(
          libraryRootId: 'cccccccccccccccccccccccccccccccc',
          scope: dto.SourceEntriesChangeScopeDto.entireRootHierarchy(),
        ),
      ),
    );
    expect(entries.payload, isA<RuntimeEventPayloadSourceEntriesChanged>());
  });

  test(
    'source-entry scope entryChildren preserves the exact parent identity',
    () {
      final event = runtimeEventFromDto(
        dto.RuntimeEventDto(
          runtimeInstanceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          sequence: BigInt.from(3),
          occurredAtMs: BigInt.from(3),
          payload: dto.RuntimeEventPayloadDto.sourceEntriesChanged(
            libraryRootId: 'cccccccccccccccccccccccccccccccc',
            scope: dto.SourceEntriesChangeScopeDto.entryChildren(
              'dddddddddddddddddddddddddddddddd',
            ),
          ),
        ),
      );

      final payload = event.payload as RuntimeEventPayloadSourceEntriesChanged;
      expect(
        payload.scope,
        SourceEntriesChangeScope.entryChildren(
          parentSourceEntryId: const SourceEntryId(
            'dddddddddddddddddddddddddddddddd',
          ),
        ),
      );
    },
  );

  test(
    'source-entry row DTO maps safe fields and reserved status stays null',
    () {
      final entry = sourceEntryFromDto(
        const dto.SourceEntryDto(
          sourceEntryId: '11111111111111111111111111111111',
          parentSourceEntryId: '22222222222222222222222222222222',
          displayName: 'a.bin',
          displayLocation: 'a.bin',
          kind: dto.SourceEntryKindDto.file,
          classification: dto.SourceEntryClassificationDto.unknown,
          boundedStatusSummary: null,
        ),
      );

      expect(
        entry.sourceEntryId,
        const SourceEntryId('11111111111111111111111111111111'),
      );
      expect(
        entry.parentSourceEntryId,
        const SourceEntryId('22222222222222222222222222222222'),
      );
      expect(entry.displayName, 'a.bin');
      expect(entry.kind, SourceEntryKind.file);
      expect(entry.classification, SourceEntryClassification.unknown);
    },
  );

  test('source-entry detail DTO maps safe fields without provenance', () {
    final detail = sourceEntryDetailFromDto(
      const dto.SourceEntryDetailDto(
        sourceEntryId: '11111111111111111111111111111111',
        parentSourceEntryId: null,
        displayName: 'Sub',
        displayLocation: 'Sub',
        kind: dto.SourceEntryKindDto.directory,
        classification: dto.SourceEntryClassificationDto.container,
      ),
    );

    expect(detail.kind, SourceEntryKind.directory);
    expect(detail.classification, SourceEntryClassification.container);
  });

  test('source-entry children page preserves the opaque cursor', () {
    final page = sourceEntryChildrenPageFromDto(
      dto.SourceEntryChildrenPageDto(
        items: const [
          dto.SourceEntryDto(
            sourceEntryId: '11111111111111111111111111111111',
            displayName: 'a.bin',
            displayLocation: 'a.bin',
            kind: dto.SourceEntryKindDto.file,
            classification: dto.SourceEntryClassificationDto.unknown,
          ),
        ],
        nextCursor: 'v1:1700000000:11111111111111111111111111111111',
      ),
    );

    expect(page.items.single.displayName, 'a.bin');
    expect(page.nextCursor, 'v1:1700000000:11111111111111111111111111111111');
  });

  test('source-entry DTO rejects malformed identity as contract mismatch', () {
    expect(
      () => sourceEntryFromDto(
        const dto.SourceEntryDto(
          sourceEntryId: 'not-an-id',
          displayName: 'a.bin',
          displayLocation: 'a.bin',
          kind: dto.SourceEntryKindDto.file,
          classification: dto.SourceEntryClassificationDto.unknown,
        ),
      ),
      throwsA(
        isA<TransportFailure>().having(
          (failure) => failure.kind,
          'kind',
          TransportFailureKind.contractMismatch,
        ),
      ),
    );
  });

  test('source-entry kind and classification wire enums are exhaustive', () {
    expect(
      sourceEntryKindFromDto(dto.SourceEntryKindDto.directory),
      SourceEntryKind.directory,
    );
    expect(
      sourceEntryKindFromDto(dto.SourceEntryKindDto.linkLike),
      SourceEntryKind.linkLike,
    );
    expect(
      sourceEntryClassificationFromDto(
        dto.SourceEntryClassificationDto.contentCandidate,
      ),
      SourceEntryClassification.contentCandidate,
    );
    expect(
      sourceEntryClassificationFromDto(
        dto.SourceEntryClassificationDto.supportingEntry,
      ),
      SourceEntryClassification.supportingEntry,
    );
  });
}
