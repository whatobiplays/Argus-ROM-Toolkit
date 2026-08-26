import 'package:argus/core/bridge/generated/frb_generated.dart' as frb;
import 'package:argus/core/bridge/generated/lib.dart' as dto;
import 'package:argus/core/bridge/src/frb_argus_client_gateway.dart';
import 'package:argus/core/client/client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'dart:typed_data';

void main() {
  test(
    'enrichment DTOs map provenance, readiness, and bounded artwork bytes',
    () {
      final metadata = resolvedMetadataFromDto(
        dto.ResolvedMetadataDto(
          displayTitle: 'Resolved Game',
          sortTitle: 'resolved game',
          description: 'Description',
          releaseDate: null,
          developers: const <String>['Developer'],
          publishers: const <String>['Publisher'],
          genres: const <String>['Action'],
          presentationRegion: 'us',
          presentationLanguages: const <String>['en'],
          fieldProvenance: const <dto.MetadataFieldProvenanceDto>[
            dto.MetadataFieldProvenanceDto(
              field: 'display_title',
              providerId: 'gametdb',
              externalGameId: 'tdb-1',
              source: 'fixture:gametdb',
            ),
          ],
          resolutionRevision: BigInt.from(2),
          resolvedAt: 100,
          providerId: 'gametdb',
        ),
      );
      final readiness = metadataProviderReadinessFromDto(
        const dto.MetadataProviderReadinessDto(
          providerId: 'gametdb',
          enabled: true,
          capabilityReadiness: <dto.ProviderCapabilityReadinessDto>[
            dto.ProviderCapabilityReadinessDto(
              capability: 'metadata_refresh',
              state: 'ready',
            ),
          ],
          credentialConfigured: false,
        ),
      );
      final artwork = resolvedArtworkFromDto(
        dto.ResolvedArtworkDto(
          artworkType: 'cover_front',
          referenceId: 'gametdb:tdb-1:cover',
          assetId: 'aa' * 32,
          ordering: 0,
          selectionReason: 'deterministic_policy',
          resolutionRevision: BigInt.from(2),
          resolvedAt: 100,
        ),
      );
      final bytes = artworkAssetBytesFromDto(
        dto.ArtworkAssetBytesDto(
          assetId: 'aa' * 32,
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
          mimeType: 'image/png',
          width: 1,
          height: 1,
        ),
      );

      expect(metadata.displayTitle, 'Resolved Game');
      expect(metadata.fieldProvenance.single.source, 'fixture:gametdb');
      expect(readiness.providerId, 'gametdb');
      expect(
        readiness.capabilityReadiness.single.state,
        ProviderReadinessState.ready,
      );
      expect(artwork.assetId, 'aa' * 32);
      expect(bytes.bytes, <int>[1, 2, 3]);
      expect(bytes.mimeType, 'image/png');
    },
  );

  test('logical-library row DTO maps durable fallback facts', () {
    final row = gameLibraryRowFromDto(
      const dto.GameLibraryRowDto(
        gameId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        displayTitle: 'Fallback Game Boy',
        platformId: dto.PlatformIdDto.nintendoGb,
        hydrationState: dto.HydrationStateDto.partiallyHydrated,
        contentCount: 1,
        sourceCount: 2,
        availabilityState: dto.GameAvailabilityStateDto.unavailable,
        updatedAtMs: 1234,
      ),
    );

    expect(row.gameId, const GameId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'));
    expect(row.displayTitle, 'Fallback Game Boy');
    expect(row.platformId, PlatformId.nintendoGb);
    expect(row.hydrationState, HydrationState.partiallyHydrated);
    expect(row.contentCount, 1);
    expect(row.sourceCount, 2);
    expect(row.availabilityState, AvailabilityState.unavailable);
    expect(row.updatedAtMs, 1234);
  });

  test(
    'logical-library mapper covers the complete cartridge platform matrix',
    () {
      const cases = <(dto.PlatformIdDto, PlatformId)>[
        (dto.PlatformIdDto.nintendoNes, PlatformId.nintendoNes),
        (dto.PlatformIdDto.nintendoFds, PlatformId.nintendoFds),
        (dto.PlatformIdDto.nintendoSnes, PlatformId.nintendoSnes),
        (dto.PlatformIdDto.nintendoGb, PlatformId.nintendoGb),
        (dto.PlatformIdDto.nintendoGbc, PlatformId.nintendoGbc),
        (dto.PlatformIdDto.nintendoGba, PlatformId.nintendoGba),
        (dto.PlatformIdDto.nintendoN64, PlatformId.nintendoN64),
        (dto.PlatformIdDto.nintendoNds, PlatformId.nintendoNds),
        (dto.PlatformIdDto.nintendo3Ds, PlatformId.nintendo3ds),
        (dto.PlatformIdDto.segaSms, PlatformId.segaSms),
        (dto.PlatformIdDto.segaGameGear, PlatformId.segaGameGear),
        (dto.PlatformIdDto.segaGenesis, PlatformId.segaGenesis),
        (dto.PlatformIdDto.sega32X, PlatformId.sega32x),
      ];

      for (final (wire, expected) in cases) {
        final row = gameLibraryRowFromDto(
          dto.GameLibraryRowDto(
            gameId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            displayTitle: 'Fixture',
            platformId: wire,
            hydrationState: dto.HydrationStateDto.unmatched,
            contentCount: 1,
            sourceCount: 1,
            availabilityState: dto.GameAvailabilityStateDto.available,
            updatedAtMs: 1,
          ),
        );
        expect(row.platformId, expected);
      }

      expect(
        contentTypeFromDto(dto.ContentTypeDto.magneticDiskImage),
        ContentType.magneticDiskImage,
      );
    },
  );

  test(
    'logical-game DTO preserves independent content states and summaries',
    () {
      final detail = gameDetailFromDto(
        const dto.GameDetailDto(
          gameId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          platformId: dto.PlatformIdDto.nintendoGbc,
          lifecycle: dto.GameLifecycleDto.active,
          hydrationState: dto.HydrationStateDto.partiallyHydrated,
          fallbackTitle: 'Local fallback',
          memberships: [
            dto.GameMembershipSummaryDto(
              gameContentId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              relationship: dto.MembershipRelationshipDto.primary,
              groupingBasis: dto.GroupingBasisDto.provisional,
              groupingRevision: 1,
            ),
          ],
          content: [
            dto.ContentSummaryDto(
              gameContentId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              platformId: dto.PlatformIdDto.nintendoGbc,
              contentType: dto.ContentTypeDto.cartridgeImage,
              presence: dto.ContentPresenceDto.orphaned,
              identification: dto.IdentificationStateDto.needsReidentification,
              sourceCount: 0,
              identity: null,
              provenance: null,
            ),
          ],
          availabilityState: dto.GameAvailabilityStateDto.inactiveOrphan,
        ),
      );

      expect(detail.gameId, const GameId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'));
      expect(detail.platformId, PlatformId.nintendoGbc);
      expect(detail.lifecycle, GameLifecycle.active);
      expect(detail.hydrationState, HydrationState.partiallyHydrated);
      expect(detail.fallbackTitle, 'Local fallback');
      expect(
        detail.memberships.single.relationship,
        MembershipRelationship.primary,
      );
      expect(
        detail.memberships.single.groupingBasis,
        GroupingBasis.provisional,
      );
      expect(detail.content.single.presence, ContentPresence.orphaned);
      expect(
        detail.content.single.identification,
        IdentificationState.needsReidentification,
      );
      expect(detail.content.single.identity, isNull);
      expect(detail.content.single.provenance, isNull);
      expect(detail.availabilityState, AvailabilityState.inactiveOrphan);
    },
  );

  test('logical-game DTO maps current identity and exact proving provenance', () {
    final summary = contentSummaryFromDto(
      const dto.ContentSummaryDto(
        gameContentId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        platformId: dto.PlatformIdDto.nintendoGba,
        contentType: dto.ContentTypeDto.cartridgeImage,
        presence: dto.ContentPresenceDto.available,
        identification: dto.IdentificationStateDto.identified,
        sourceCount: 2,
        identity: dto.ContentIdentitySummaryDto(
          schemeId: 'argus.content.identity.nintendo-gba.cartridge.v1',
          revision: 1,
          digest:
              '9999999999999999999999999999999999999999999999999999999999999999',
        ),
        provenance: dto.ContentProvenanceSummaryDto(
          sourceEntryId: 'cccccccccccccccccccccccccccccccc',
          associationKey: 'raw',
          sourceFingerprint: 'v1:32:1',
          lastObservedScanId: 'dddddddddddddddddddddddddddddddd',
        ),
      ),
    );

    expect(
      summary.identity?.schemeId,
      'argus.content.identity.nintendo-gba.cartridge.v1',
    );
    expect(summary.identity?.revision, 1);
    expect(summary.identity?.digest, startsWith('99'));
    expect(
      summary.provenance?.sourceEntryId,
      const SourceEntryId('cccccccccccccccccccccccccccccccc'),
    );
    expect(summary.provenance?.associationKey, 'raw');
    expect(summary.provenance?.sourceFingerprint, 'v1:32:1');
    expect(
      summary.provenance?.lastObservedScanId,
      'dddddddddddddddddddddddddddddddd',
    );
  });

  test('logical-game lookup DTO preserves Found and Redirected outcomes', () {
    const found = dto.GetGameResultDto_Found(
      dto.GameDetailDto(
        gameId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        platformId: dto.PlatformIdDto.nintendoGb,
        lifecycle: dto.GameLifecycleDto.active,
        hydrationState: dto.HydrationStateDto.partiallyHydrated,
        fallbackTitle: 'Found',
        memberships: [],
        content: [],
        availabilityState: dto.GameAvailabilityStateDto.available,
      ),
    );
    const redirected = dto.GetGameResultDto_Redirected(
      canonicalGameId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );

    expect(getGameResultFromDto(found), isA<GetGameFound>());
    expect(
      (getGameResultFromDto(redirected) as GetGameRedirected).canonicalGameId,
      const GameId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
    );
  });

  test(
    'full BE-008 query DTO mapping keeps baseline and unsupported inputs explicit',
    () {
      final baseline = listGamesRequestToDto(const ListGamesRequest());
      expect(baseline.scope, isA<dto.LibraryScopeDto_All>());
      expect(baseline.searchText, isNull);
      expect(baseline.filters.platformIds, isEmpty);
      expect(baseline.filters.regions, isEmpty);
      expect(baseline.sort.field, dto.LibrarySortFieldDto.displayTitle);
      expect(baseline.sort.direction, dto.LibrarySortDirectionDto.ascending);
      expect(baseline.pageSize, 50);

      final unsupported = listGamesRequestToDto(
        const ListGamesRequest(
          scope: LibraryScope.platform('nintendo.gb'),
          searchText: 'zelda',
          filters: LibraryFilter(platformIds: ['nintendo.gb']),
          sort: LibrarySort(
            field: LibrarySortField.platform,
            direction: LibrarySortDirection.descending,
          ),
          cursor: 'v1:Fallback Game Boy:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          pageSize: 7,
        ),
      );
      expect(unsupported.scope, isA<dto.LibraryScopeDto_Platform>());
      expect(
        (unsupported.scope as dto.LibraryScopeDto_Platform).platformId,
        'nintendo.gb',
      );
      expect(unsupported.searchText, 'zelda');
      expect(unsupported.filters.platformIds, ['nintendo.gb']);
      expect(unsupported.sort.field, dto.LibrarySortFieldDto.platform);
      expect(
        unsupported.sort.direction,
        dto.LibrarySortDirectionDto.descending,
      );
      expect(unsupported.cursor, startsWith('v1:'));
      expect(unsupported.pageSize, 7);
    },
  );

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

  test(
    'provider-dependent Sources calls refresh mounts before the operation',
    () async {
      final api = _SourcesRecordingRustLibApi();
      var reads = 0;
      final gateway = FrbArgusClientGateway(
        api: api,
        initializeNative: () async {},
        mountedVolumesReader: () async {
          reads++;
          return const [
            MountedLocalFilesystemVolumeFact(
              providerVolumeId: 'primary',
              transientMountPath: '/storage/emulated/0',
              safeDisplayName: 'Internal storage',
              isPrimary: true,
              isRemovable: false,
            ),
          ];
        },
      );

      await gateway.listLibraryRoots(offset: 0, pageSize: 10);

      expect(reads, 1);
      expect(api.calls, ['sync', 'list']);
      expect(api.syncedVolumes.single.providerVolumeId, 'primary');
    },
  );

  test(
    'Add & Scan and single-root Scan refresh mounts before admission',
    () async {
      final api = _SourcesRecordingRustLibApi();
      final gateway = FrbArgusClientGateway(
        api: api,
        initializeNative: () async {},
        mountedVolumesReader: () async => const [
          MountedLocalFilesystemVolumeFact(
            providerVolumeId: 'primary',
            transientMountPath: '/storage/emulated/0',
            safeDisplayName: 'Internal storage',
            isPrimary: true,
            isRemovable: false,
          ),
        ],
      );

      await gateway.addLocalLibraryRootAndScan(
        const LocalFilesystemRootSelection.providerSelection('selection'),
      );
      await gateway.startLibraryScan(
        const LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
      );

      expect(api.calls, ['sync', 'addAndScan', 'sync', 'startScan']);
    },
  );

  test('Add & Scan is not invoked after mount refresh failure', () async {
    final api = _SourcesRecordingRustLibApi();
    final gateway = FrbArgusClientGateway(
      api: api,
      initializeNative: () async {},
      mountedVolumesReader: () async => throw StateError('discovery failed'),
    );

    await expectLater(
      gateway.addLocalLibraryRootAndScan(
        const LocalFilesystemRootSelection.providerSelection('selection'),
      ),
      throwsA(isA<TransportFailure>()),
    );
    expect(api.calls, isEmpty);
  });

  test('single-root Scan is not invoked after mount refresh failure', () async {
    final api = _SourcesRecordingRustLibApi();
    final gateway = FrbArgusClientGateway(
      api: api,
      initializeNative: () async {},
      mountedVolumesReader: () async => throw StateError('discovery failed'),
    );

    await expectLater(
      gateway.startLibraryScan(
        const LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
      ),
      throwsA(isA<TransportFailure>()),
    );
    expect(api.calls, isEmpty);
  });

  test(
    'concurrent provider-dependent Sources calls share one mount refresh',
    () async {
      final api = _SourcesRecordingRustLibApi();
      final release = Completer<void>();
      var reads = 0;
      final gateway = FrbArgusClientGateway(
        api: api,
        initializeNative: () async {},
        mountedVolumesReader: () async {
          reads++;
          await release.future;
          return const [
            MountedLocalFilesystemVolumeFact(
              providerVolumeId: 'primary',
              transientMountPath: '/storage/emulated/0',
              safeDisplayName: 'Internal storage',
              isPrimary: true,
              isRemovable: false,
            ),
          ];
        },
      );

      final first = gateway.listLibraryRoots(offset: 0, pageSize: 10);
      final second = gateway.listLibraryRoots(offset: 0, pageSize: 10);
      await Future<void>.delayed(Duration.zero);
      release.complete();
      await Future.wait([first, second]);

      expect(reads, 1);
      expect(api.calls.where((call) => call == 'sync'), hasLength(1));
      expect(api.calls.where((call) => call == 'list'), hasLength(2));
    },
  );

  test('mount discovery failures prevent a stale Sources operation', () async {
    final api = _SourcesRecordingRustLibApi();
    final gateway = FrbArgusClientGateway(
      api: api,
      initializeNative: () async {},
      mountedVolumesReader: () async => throw StateError('discovery failed'),
    );

    await expectLater(
      gateway.listLibraryRoots(offset: 0, pageSize: 10),
      throwsA(isA<TransportFailure>()),
    );
    expect(api.calls, isEmpty);
  });

  test(
    'data-directory override precedes host-standard Android data directory',
    () async {
      final api = _RecordingRustLibApi();
      final gateway = FrbArgusClientGateway(
        api: api,
        initializeNative: () async {},
        dataDirectoryOverride: '/tmp/explicit',
        standardApplicationDataDirectory:
            '/data/user/0/com.argusromtoolkit.argus/files/argus',
      );

      await gateway.initialize();

      expect(api.lastCall, 'crateInitializeWithDataDirectory');
      expect(api.lastArgument, '/tmp/explicit');
    },
  );

  test(
    'Android diagnostics sharing exports through Rust before native publication',
    () async {
      final api = _RecordingRustLibApi();
      var publicationCalls = 0;
      final gateway = FrbArgusClientGateway(
        api: api,
        initializeNative: () async {},
        publishCompletedDiagnostics: () async {
          publicationCalls++;
        },
      );

      final export = await gateway.exportStartupDiagnosticsForSharing(
        const RuntimeInstanceId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
      );

      expect(api.lastCall, 'crateExportStartupDiagnosticsForSharing');
      expect(api.lastNamedArguments?.keys, {
        const Symbol('expectedRuntimeInstanceId'),
      });
      expect(export.destinationClassification, 'backend_owned_diagnostics');
      expect(publicationCalls, 1);
    },
  );

  test(
    'host-standard Android data directory is used without an override',
    () async {
      final api = _RecordingRustLibApi();
      final gateway = FrbArgusClientGateway(
        api: api,
        initializeNative: () async {},
        standardApplicationDataDirectory:
            '/data/user/0/com.argusromtoolkit.argus/files/argus',
      );

      await gateway.initialize();

      expect(api.lastCall, 'crateInitializeWithStandardDataDirectory');
      expect(
        api.lastArgument,
        '/data/user/0/com.argusromtoolkit.argus/files/argus',
      );
    },
  );

  test('plain initialization calls the default bridge entrypoint', () async {
    final api = _RecordingRustLibApi();
    final gateway = FrbArgusClientGateway(
      api: api,
      initializeNative: () async {},
    );

    await gateway.initialize();

    expect(api.lastCall, 'crateInitialize');
  });

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

  test('start library scan all DTO maps admitted roots and exclusions', () {
    const errorDto = dto.ApplicationErrorDto(
      code: 'ARGUS.V1.CONFIGURATION.INVALID',
      category: 'configuration',
      severity: 'Error',
      recoverability: 'UserAction',
      retryPolicy: 'Never',
      messageKey: 'errors.configuration.invalid',
      traceId: '09090909090909090909090909090909',
      safeContext: [],
    );
    final admitted = startLibraryScanAllResultFromDto(
      const dto.StartLibraryScanAllResultDto_Admitted(
        operationHandle: dto.OperationHandleDto(
          jobRunId: '01010101010101010101010101010101',
          operationType: 'library_scan',
        ),
        admittedRoots: ['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'],
        exclusions: [
          dto.LibraryScanAdmissionExclusionDto(
            libraryRootId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            reason: 'invalid_configuration',
            applicationError: errorDto,
          ),
        ],
      ),
    );
    expect(admitted, isA<StartLibraryScanAllResultAdmitted>());
    final value = admitted as StartLibraryScanAllResultAdmitted;
    expect(value.handle.jobRunId.value, '01010101010101010101010101010101');
    expect(
      value.admittedRoots.single.value,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    final exclusion = value.exclusions.single;
    expect(exclusion.reason, 'invalid_configuration');
    expect(
      exclusion.applicationError?.code.value,
      'ARGUS.V1.CONFIGURATION.INVALID',
    );

    final nothing = startLibraryScanAllResultFromDto(
      const dto.StartLibraryScanAllResultDto_NothingEligible(exclusions: []),
    );
    expect(nothing, isA<StartLibraryScanAllResultNothingEligible>());
  });

  test('scan all request resolution DTO maps admission and no-admission', () {
    final admitted = libraryScanAllRequestResolutionFromDto(
      const dto.LibraryScanAllRequestResolutionDto_Admitted(
        operationHandle: dto.OperationHandleDto(
          jobRunId: '02020202020202020202020202020202',
          operationType: 'library_scan',
        ),
        admittedRoots: ['aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'],
        exclusions: [],
      ),
    );
    expect(admitted, isA<LibraryScanAllRequestResolutionAdmitted>());
    expect(
      libraryScanAllRequestResolutionFromDto(
        const dto.LibraryScanAllRequestResolutionDto_NothingAdmitted(),
      ),
      isA<LibraryScanAllRequestResolutionNothingAdmitted>(),
    );
  });

  test('scan all request identity validates the canonical alphabet', () {
    expect(ScanAllRequestIdentity.tryParse('request-1.ab_c'), isNotNull);
    expect(ScanAllRequestIdentity.tryParse(''), isNull);
    expect(ScanAllRequestIdentity.tryParse('has spaces'), isNull);
    expect(ScanAllRequestIdentity.tryParse('x' * 257), isNull);
    expect(ScanAllRequestIdentity.tryParse('x' * 256), isNotNull);
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

  test('local filesystem selection maps both closed union variants', () {
    expect(
      selectionToDto(const LocalFilesystemRootSelection('/tmp/games')),
      const dto.LocalFilesystemRootSelectionDto.path(
        selectedFolderPath: '/tmp/games',
      ),
    );
    expect(
      selectionToDto(
        const LocalFilesystemRootSelection.providerSelection('opaque-root'),
      ),
      const dto.LocalFilesystemRootSelectionDto.providerSelection(
        selectionIdentity: 'opaque-root',
      ),
    );
  });

  test(
    'browse DTOs map only opaque identities and safe display projections',
    () {
      final page = localFilesystemBrowsePageFromDto(
        const dto.LocalFilesystemBrowsePageDto(
          current: dto.LocalFilesystemBrowseRootDto(
            location: 'opaque-root',
            displayName: 'Internal storage',
            safeLocationPresentation: 'Internal storage',
          ),
          breadcrumbs: [
            dto.LocalFilesystemBrowseBreadcrumbDto(
              location: 'opaque-root',
              displayName: 'Internal storage',
            ),
          ],
          directories: [
            dto.LocalFilesystemBrowseDirectoryDto(
              location: 'opaque-child',
              displayName: 'Games',
            ),
          ],
          nextCursor: 'opaque-cursor',
        ),
      );

      expect(page.current.location.value, 'opaque-root');
      expect(page.current.safeLocationPresentation, 'Internal storage');
      expect(page.breadcrumbs.single.displayName, 'Internal storage');
      expect(page.directories.single.location.value, 'opaque-child');
      expect(page.nextCursor, 'opaque-cursor');
    },
  );

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

/// Records the generated bridge entrypoint invoked by the gateway without
/// loading any native library.
final class _RecordingRustLibApi implements frb.RustLibApi {
  String? lastCall;
  Object? lastArgument;
  Map<Symbol, dynamic>? lastNamedArguments;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final method = invocation.memberName;
    if (method == #crateInitializeWithDataDirectory) {
      lastCall = 'crateInitializeWithDataDirectory';
      lastArgument = invocation.namedArguments[const Symbol('dataDirectory')];
    } else if (method == #crateInitializeWithStandardDataDirectory) {
      lastCall = 'crateInitializeWithStandardDataDirectory';
      lastArgument = invocation.namedArguments[const Symbol('dataDirectory')];
    } else if (method == #crateInitialize) {
      lastCall = 'crateInitialize';
    } else if (method == #crateExportStartupDiagnosticsForSharing) {
      lastCall = 'crateExportStartupDiagnosticsForSharing';
      lastNamedArguments = invocation.namedArguments;
      return Future<dto.DiagnosticsExportDto>.value(
        const dto.DiagnosticsExportDto(
          outcome: dto.DiagnosticsExportOutcomeDto.created,
          destinationClassification: 'backend_owned_diagnostics',
        ),
      );
    }
    return Future<dto.RuntimeStateDto>.value(
      const dto.RuntimeStateDto(
        runtimeInstanceId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        lifecycleState: dto.RuntimeLifecycleDto.ready,
        startupPhase: null,
        startupFailure: null,
      ),
    );
  }
}

final class _SourcesRecordingRustLibApi implements frb.RustLibApi {
  final List<String> calls = [];
  final List<dto.MountedLocalFilesystemVolumeDto> syncedVolumes = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final method = invocation.memberName;
    if (method == #crateSyncLocalFilesystemMountedVolumes) {
      calls.add('sync');
      final request =
          invocation.namedArguments[const Symbol('request')]
              as dto.SyncLocalFilesystemMountedVolumesRequestDto;
      syncedVolumes
        ..clear()
        ..addAll(request.volumes);
      return Future<void>.value();
    }
    if (method == #crateListLocalFilesystemBrowseRoots) {
      calls.add('browseRoots');
      return Future<List<dto.LocalFilesystemBrowseRootDto>>.value(const []);
    }
    if (method == #crateAddLocalLibraryRootAndScan) {
      calls.add('addAndScan');
      return Future<dto.AddLocalLibraryRootAndScanResultDto>.value(
        dto.AddLocalLibraryRootAndScanResultDto.addedAndScanAdmitted(
          const dto.LibraryRootDto(
            libraryRootId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            displayName: 'Games',
            safeLocationPresentation: 'Internal storage/Games',
            availability: dto.LibraryRootAvailabilityDto.available,
          ),
          const dto.OperationHandleDto(
            jobRunId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            operationType: 'library_scan',
          ),
        ),
      );
    }
    if (method == #crateStartLibraryScan) {
      calls.add('startScan');
      return Future<dto.StartLibraryScanResultDto>.value(
        const dto.StartLibraryScanResultDto.admitted(
          dto.OperationHandleDto(
            jobRunId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            operationType: 'library_scan',
          ),
        ),
      );
    }
    if (method == #crateListLibraryRoots) {
      calls.add('list');
      return Future<dto.LibraryRootPageDto>.value(
        const dto.LibraryRootPageDto(
          items: [],
          offset: 0,
          pageSize: 10,
          totalCount: 0,
        ),
      );
    }
    return Future<void>.value();
  }
}
