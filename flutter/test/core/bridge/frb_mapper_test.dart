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
      removeLibraryRootResultFromDto(dto.RemoveLibraryRootResultDto.removed),
      RemoveLibraryRootResult.removed,
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
}
