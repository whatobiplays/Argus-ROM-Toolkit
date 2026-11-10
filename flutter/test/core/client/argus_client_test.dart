import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'jobs_gateway_stub.dart';
import 'sources_gateway_stub.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'same generation initialization keeps one logical event connection',
    () async {
      final gateway = FakeGateway(RuntimeInstanceId('a' * 32));
      final client = ArgusClient(gateway: gateway);
      await client.initialize();
      await client.initialize();

      expect(gateway.subscribeCount, 1);
      expect(client.runtime, isA<RuntimeApi>());
      expect(client.settings, isA<SettingsApi>());
      expect(client.diagnostics, isA<DiagnosticsApi>());
      expect(client.events, isA<EventsApi>());
      await client.dispose();
    },
  );

  test(
    'transport failure is observable and reconnects the same generation',
    () async {
      final gateway = FakeGateway(RuntimeInstanceId('b' * 32));
      final client = ArgusClient(gateway: gateway);
      final events = <RuntimeEvent>[];
      final failures = <Object>[];
      final listener = client.events.events.listen(
        events.add,
        onError: failures.add,
      );
      await client.initialize();

      gateway.controllers.single.add(_event(gateway.id, 1));
      gateway.controllers.single.addError(const TransportFailure('broken'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(gateway.subscribeCount, 2);

      gateway.controllers.last.add(_event(gateway.id, 3));
      await Future<void>.delayed(Duration.zero);
      expect(events.map((event) => event.sequence), <BigInt>[
        BigInt.one,
        BigInt.from(3),
      ]);
      expect(failures.single, isA<TransportFailure>());
      await listener.cancel();
      await client.dispose();
    },
  );

  test(
    'replacement generation rebinds and retains distinct sequence domains',
    () async {
      final gateway = FakeGateway(RuntimeInstanceId('c' * 32));
      final client = ArgusClient(gateway: gateway);
      final events = <RuntimeEvent>[];
      final listener = client.events.events.listen(events.add);
      await client.initialize();

      final replacement = RuntimeInstanceId('d' * 32);
      gateway.nextState = RuntimeState.ready(runtimeInstanceId: replacement);
      await client.runtime.retryStartup(gateway.id);
      expect(gateway.subscribeCount, 2);
      gateway.controllers.last.add(_event(replacement, 1));
      await Future<void>.delayed(Duration.zero);
      expect(events.single.runtimeInstanceId, replacement);
      expect(client.boundGeneration, replacement);
      await listener.cancel();
      await client.dispose();
    },
  );

  test(
    'concurrent same-generation reconnects never overlap native streams',
    () async {
      final gateway = FakeGateway(RuntimeInstanceId('1' * 32));
      final client = ArgusClient(gateway: gateway);
      await client.initialize();

      await Future.wait<void>([
        client.reconnectEvents(),
        client.reconnectEvents(),
      ]);

      expect(gateway.maxActiveSubscriptions, 1);
      await client.dispose();
    },
  );

  test('application failures stay distinct from transport failures', () async {
    final gateway = FakeGateway(RuntimeInstanceId('e' * 32))
      ..failure = ApplicationFailure(
        ClientApplicationError(
          code: const ErrorCode('ARGUS.V1.RUNTIME.STALE_INSTANCE'),
          category: ErrorCategory.runtime,
          severity: ApplicationSeverity.error,
          recoverability: Recoverability.userAction,
          retryPolicy: RetryPolicy.never,
          messageKey: const MessageKey('errors.runtime.stale_instance'),
          traceId: const TraceId('01010101010101010101010101010101'),
          safeContext: const <SafeContextEntry>[],
        ),
      );
    final client = ArgusClient(gateway: gateway);

    await expectLater(client.initialize(), throwsA(isA<ApplicationFailure>()));
    await client.dispose();
  });

  test(
    'invalid runtime identity is exposed as a transport contract failure',
    () async {
      final gateway = FakeGateway(RuntimeInstanceId('f' * 32))
        ..nextState = RuntimeState.ready(
          runtimeInstanceId: const RuntimeInstanceId(
            '00000000000000000000000000000000',
          ),
        );
      final client = ArgusClient(gateway: gateway);

      await expectLater(client.initialize(), throwsA(isA<TransportFailure>()));
      await client.dispose();
    },
  );

  test(
    'ClientBootstrap delegates through one root initialization path',
    () async {
      final gateway = FakeGateway(RuntimeInstanceId('9' * 32));
      final client = ArgusClient(gateway: gateway);
      final bootstrap = client as ClientBootstrap;

      final state = await bootstrap.initialize();

      expect(state, isA<RuntimeStateReady>());
      expect(gateway.initializeCalls, 1);
      await client.dispose();
    },
  );

  test('settings update returns no authoritative state echo', () async {
    final gateway = FakeGateway(RuntimeInstanceId('8' * 32));
    final client = ArgusClient(gateway: gateway);

    await client.settings.updateAppearanceSettings(
      const AppearanceSettings(themeMode: ThemeMode.dark),
    );

    expect(gateway.updateCalls, 1);
    await client.dispose();
  });

  test('provider readiness and artwork capabilities remain bounded', () async {
    final gateway = FakeGateway(RuntimeInstanceId('p' * 32));
    final client = ArgusClient(gateway: gateway);

    final readiness = await client.metadataProviders
        .listMetadataProviderReadiness();
    final credential = await client.metadataProviders.setSteamgriddbCredential(
      const <int>[1, 2, 3],
    );
    final removed = await client.metadataProviders
        .removeSteamgriddbCredential();
    final asset = await client.artwork.getArtworkAssetBytes('aa' * 32);

    expect(readiness.single.providerId, 'gametdb');
    expect(credential.credentialConfigured, isTrue);
    expect(removed.state, ProviderReadinessState.missingCredentials);
    expect(asset.bytes, <int>[1, 2, 3]);
    expect(gateway.metadataReadinessCalls, 1);
    expect(gateway.setCredentialCalls, 1);
    expect(gateway.lastCredentialLength, 3);
    expect(gateway.removeCredentialCalls, 1);
    expect(gateway.artworkBytesCalls, 1);
    await client.dispose();
  });

  test(
    'Android diagnostics sharing is additive to the desktop exporter',
    () async {
      final gateway = FakeGateway(RuntimeInstanceId('a' * 32))
        ..supportsDiagnosticsSharing = true;
      final client = ArgusClient(gateway: gateway);

      final shared = await client.diagnosticsSharing!
          .exportStartupDiagnosticsForSharing(gateway.id);
      final desktop = await client.diagnostics.exportStartupDiagnostics(
        gateway.id,
        '/tmp/desktop-diagnostics.zip',
      );

      expect(shared.destinationClassification, 'backend_owned_diagnostics');
      expect(desktop.destinationClassification, 'user_selected');
      expect(gateway.sharingCalls, 1);
      expect(gateway.destinations, ['/tmp/desktop-diagnostics.zip']);
      await client.dispose();
    },
  );

  test(
    'ambiguous settings transport failure is not automatically retried',
    () async {
      final gateway = FakeGateway(RuntimeInstanceId('7' * 32))
        ..updateFailure = const TransportFailure('ambiguous transport failure');
      final client = ArgusClient(gateway: gateway);

      await expectLater(
        client.settings.updateAppearanceSettings(
          const AppearanceSettings(themeMode: ThemeMode.light),
        ),
        throwsA(isA<TransportFailure>()),
      );
      expect(gateway.updateCalls, 1);
      await client.dispose();
    },
  );

  test('runtime recovery returns authoritative replacement state', () async {
    final replacement = RuntimeInstanceId('5' * 32);
    final gateway = FakeGateway(RuntimeInstanceId('6' * 32))
      ..nextState = RuntimeState.ready(runtimeInstanceId: replacement);
    final client = ArgusClient(gateway: gateway);

    final state = await client.runtime.retryStartup(gateway.id);

    expect((state as RuntimeStateReady).runtimeInstanceId, replacement);
    expect(gateway.retryCalls, 1);
    await client.dispose();
  });

  test('stale expected runtime identity is not silently retargeted', () async {
    final gateway = FakeGateway(RuntimeInstanceId('4' * 32))
      ..failStaleRetry = true;
    final client = ArgusClient(gateway: gateway);
    final staleId = RuntimeInstanceId('3' * 32);

    await expectLater(
      client.runtime.retryStartup(staleId),
      throwsA(isA<ApplicationFailure>()),
    );
    expect(gateway.retryCalls, 1);
    expect(client.boundGeneration, isNull);
    await client.dispose();
  });

  test(
    'revision-fenced list and detail reads keep the supplied view token',
    () async {
      final gateway = _RevisionFencedLibraryGatewayFake(
        RuntimeInstanceId('v' * 32),
      );
      final client = ArgusClient(gateway: gateway);
      const firstRequest = ListGamesRequest();

      final firstPage = await client.listGamesRevisionFenced(firstRequest);
      final continuationRequest = ListGamesRequest(
        cursor: firstPage.page.nextCursor,
      );
      final continuationPage = await client.listGamesRevisionFenced(
        continuationRequest,
        viewToken: firstPage.viewToken,
      );
      final detail = await client.getGameWithView(
        gateway.gameId,
        continuationPage.viewToken,
      );

      expect(firstPage.page, same(gateway.revisionPage));
      expect(firstPage.viewToken, 'view-token');
      expect(continuationPage.viewToken, firstPage.viewToken);
      expect(gateway.revisionRequests, <ListGamesRequest>[
        firstRequest,
        continuationRequest,
      ]);
      expect(gateway.revisionViewTokens, <String?>[null, 'view-token']);
      expect(detail, same(gateway.legacyGameResult));
      expect(gateway.detailGameIds, <GameId>[gateway.gameId]);
      expect(gateway.detailViewTokens, <String>['view-token']);
      expect(gateway.legacyListRequests, isEmpty);
      expect(gateway.legacyGameIds, isEmpty);
      await client.dispose();
    },
  );

  test(
    'revision-fenced reads fail closed when the gateway lacks the capability',
    () async {
      final gateway = _LibraryGatewayFake(RuntimeInstanceId('w' * 32));
      final client = ArgusClient(gateway: gateway);

      await expectLater(
        client.listGamesRevisionFenced(
          const ListGamesRequest(cursor: 'next-page'),
          viewToken: 'existing-view',
        ),
        throwsA(
          isA<TransportFailure>().having(
            (failure) => failure.kind,
            'kind',
            TransportFailureKind.contractMismatch,
          ),
        ),
      );
      await expectLater(
        client.getGameWithView(gateway.gameId, 'existing-view'),
        throwsA(
          isA<TransportFailure>().having(
            (failure) => failure.kind,
            'kind',
            TransportFailureKind.contractMismatch,
          ),
        ),
      );

      expect(gateway.legacyListRequests, isEmpty);
      expect(gateway.legacyGameIds, isEmpty);
      await client.dispose();
    },
  );

  test(
    'revision-fenced application errors retain their stable codes',
    () async {
      final staleView = _libraryApplicationFailure(
        'ARGUS.V1.LIBRARY.STALE_VIEW',
      );
      final invalidToken = _libraryApplicationFailure(
        'ARGUS.V1.LIBRARY.INVALID_VIEW_TOKEN',
      );
      final gateway =
          _RevisionFencedLibraryGatewayFake(RuntimeInstanceId('y' * 32))
            ..revisionListFailure = staleView
            ..revisionDetailFailure = invalidToken;
      final client = ArgusClient(gateway: gateway);

      await expectLater(
        client.listGamesRevisionFenced(const ListGamesRequest()),
        throwsA(
          isA<ApplicationFailure>().having(
            (failure) => failure.error.code.value,
            'code',
            'ARGUS.V1.LIBRARY.STALE_VIEW',
          ),
        ),
      );
      await expectLater(
        client.getGameWithView(gateway.gameId, 'view-token'),
        throwsA(
          isA<ApplicationFailure>().having(
            (failure) => failure.error.code.value,
            'code',
            'ARGUS.V1.LIBRARY.INVALID_VIEW_TOKEN',
          ),
        ),
      );
      gateway.revisionDetailFailure = _libraryApplicationFailure(
        'ARGUS.V1.INTERNAL.UNEXPECTED',
      );
      await expectLater(
        client.getGameWithView(gateway.gameId, 'view-token'),
        throwsA(
          isA<ApplicationFailure>().having(
            (failure) => failure.error.code.value,
            'code',
            'ARGUS.V1.INTERNAL.UNEXPECTED',
          ),
        ),
      );
      await client.dispose();
    },
  );

  test(
    'legacy logical-library list and detail reads remain tokenless',
    () async {
      final gateway = _LibraryGatewayFake(RuntimeInstanceId('x' * 32));
      final client = ArgusClient(gateway: gateway);
      const request = ListGamesRequest(searchText: 'classic');

      final page = await client.library.listGames(request);
      final libraryDetail = await client.library.getGame(gateway.gameId);
      final gameDetail = await client.games.getGame(gateway.gameId);

      expect(page, same(gateway.legacyPage));
      expect(libraryDetail, same(gateway.legacyGameResult));
      expect(gameDetail, same(gateway.legacyGameResult));
      expect(gateway.legacyListRequests, <ListGamesRequest>[request]);
      expect(gateway.legacyGameIds, <GameId>[gateway.gameId, gateway.gameId]);
      await client.dispose();
    },
  );
}

RuntimeEvent _event(RuntimeInstanceId id, int sequence) => RuntimeEvent(
  runtimeInstanceId: id,
  sequence: BigInt.from(sequence),
  occurredAtMs: BigInt.from(sequence),
  payload: const RuntimeEventPayload.appearanceSettingsChanged(),
);

ApplicationFailure _libraryApplicationFailure(String code) =>
    ApplicationFailure(
      ClientApplicationError(
        code: ErrorCode(code),
        category: ErrorCategory.operation,
        severity: ApplicationSeverity.warning,
        recoverability: Recoverability.retry,
        retryPolicy: RetryPolicy.userInitiated,
        messageKey: const MessageKey('errors.library.view'),
        traceId: const TraceId('01010101010101010101010101010101'),
        safeContext: const <SafeContextEntry>[],
      ),
    );

final class FakeGateway
    with SourcesGatewayStub, JobsGatewayStub
    implements
        ArgusClientGateway,
        DiagnosticsSharingGateway,
        MetadataProvidersGateway,
        ArtworkGateway {
  FakeGateway(this.id) : nextState = RuntimeState.ready(runtimeInstanceId: id);

  final RuntimeInstanceId id;
  RuntimeState nextState;
  Object? failure;
  Object? updateFailure;
  bool failStaleRetry = false;
  int initializeCalls = 0;
  int updateCalls = 0;
  int retryCalls = 0;
  int closeEventConnectionCalls = 0;
  @override
  bool supportsDiagnosticsSharing = false;
  int sharingCalls = 0;
  int metadataReadinessCalls = 0;
  int setCredentialCalls = 0;
  int removeCredentialCalls = 0;
  int lastCredentialLength = 0;
  int artworkBytesCalls = 0;
  final destinations = <String>[];
  int subscribeCount = 0;
  int activeSubscriptions = 0;
  int maxActiveSubscriptions = 0;
  final controllers = <StreamController<RuntimeEvent>>[];

  Future<T> _result<T>(T value) async {
    if (failure case final Object error) throw error;
    return value;
  }

  @override
  Future<RuntimeState> getRuntimeState() => _result(nextState);

  @override
  Future<RuntimeState> initialize() {
    initializeCalls++;
    return _result(nextState);
  }

  @override
  Future<RuntimeState> retryStartup(RuntimeInstanceId expected) {
    retryCalls++;
    if (failStaleRetry && expected != id) {
      throw ApplicationFailure(
        ClientApplicationError(
          code: const ErrorCode('ARGUS.V1.RUNTIME.STALE_INSTANCE'),
          category: ErrorCategory.runtime,
          severity: ApplicationSeverity.error,
          recoverability: Recoverability.userAction,
          retryPolicy: RetryPolicy.never,
          messageKey: const MessageKey('errors.runtime.stale_instance'),
          traceId: const TraceId('01010101010101010101010101010101'),
          safeContext: const <SafeContextEntry>[],
        ),
      );
    }
    return _result(nextState);
  }

  @override
  Future<RuntimeState> resetAppearanceSettings(RuntimeInstanceId expected) =>
      _result(nextState);

  @override
  Future<RuntimeState> exitFailedRuntime(RuntimeInstanceId expected) =>
      _result(nextState);

  @override
  Future<void> generalShutdown() => _result(null);

  @override
  Future<void> closeEventConnection() {
    closeEventConnectionCalls++;
    return Future<void>.value();
  }

  @override
  Future<AppearanceSettings> getAppearanceSettings() =>
      _result(const AppearanceSettings(themeMode: ThemeMode.system));

  @override
  Future<void> updateAppearanceSettings(AppearanceSettings settings) {
    updateCalls++;
    if (updateFailure case final Object error) throw error;
    return _result(null);
  }

  @override
  Future<List<MetadataProviderReadiness>> listMetadataProviderReadiness() {
    metadataReadinessCalls++;
    return _result(const <MetadataProviderReadiness>[
      MetadataProviderReadiness(
        providerId: 'gametdb',
        enabled: true,
        capabilityReadiness: <ProviderCapabilityReadiness>[
          ProviderCapabilityReadiness(
            capability: ProviderCapability.metadataRefresh,
            state: ProviderReadinessState.ready,
          ),
        ],
        credentialConfigured: false,
      ),
    ]);
  }

  @override
  Future<ProviderCredentialReadiness> setMetadataProviderCredential({
    required String providerId,
    required List<int> credentialInput,
  }) {
    expect(providerId, 'steamgriddb');
    setCredentialCalls++;
    lastCredentialLength = credentialInput.length;
    return _result(
      const ProviderCredentialReadiness(
        providerId: 'steamgriddb',
        state: ProviderReadinessState.ready,
        credentialConfigured: true,
      ),
    );
  }

  @override
  Future<ProviderCredentialReadiness> removeMetadataProviderCredential(
    String providerId,
  ) {
    expect(providerId, 'steamgriddb');
    removeCredentialCalls++;
    return _result(
      const ProviderCredentialReadiness(
        providerId: 'steamgriddb',
        state: ProviderReadinessState.missingCredentials,
        credentialConfigured: false,
      ),
    );
  }

  @override
  Future<ArtworkAssetBytes> getArtworkAssetBytes(String assetId) {
    artworkBytesCalls++;
    return _result(
      ArtworkAssetBytes(
        assetId: assetId,
        bytes: const <int>[1, 2, 3],
        mimeType: 'image/png',
        width: 1,
        height: 1,
      ),
    );
  }

  @override
  Future<DiagnosticsExport> exportStartupDiagnostics(
    RuntimeInstanceId expected,
    String destination,
  ) {
    destinations.add(destination);
    return _result(
      const DiagnosticsExport(
        outcome: DiagnosticsExportOutcome.created,
        destinationClassification: 'user_selected',
      ),
    );
  }

  @override
  Future<DiagnosticsExport> exportStartupDiagnosticsForSharing(
    RuntimeInstanceId expected,
  ) {
    sharingCalls++;
    return _result(
      const DiagnosticsExport(
        outcome: DiagnosticsExportOutcome.created,
        destinationClassification: 'backend_owned_diagnostics',
      ),
    );
  }

  @override
  Future<TechnicalDetails> startupTechnicalDetails(
    RuntimeInstanceId expected,
  ) => _result(const TechnicalDetails(text: 'safe'));

  @override
  Future<void> openStartupDataDirectory(RuntimeInstanceId expected) =>
      _result(null);

  @override
  Future<EventBindResult> subscribeEvents(RuntimeInstanceId generation) async {
    subscribeCount++;
    final controller = StreamController<RuntimeEvent>(
      onListen: () {
        activeSubscriptions++;
        if (activeSubscriptions > maxActiveSubscriptions) {
          maxActiveSubscriptions = activeSubscriptions;
        }
      },
      onCancel: () => activeSubscriptions--,
    );
    controllers.add(controller);
    return EventBindResult(stream: controller.stream, nativeAttached: true);
  }
}

final class _LibraryGatewayFake extends FakeGateway implements LibraryGateway {
  _LibraryGatewayFake(super.id);

  final GamePage legacyPage = const GamePage(
    items: <GameLibraryRow>[],
    nextCursor: 'legacy-next',
  );
  late final GameId gameId = GameId('g' * 32);
  late final GetGameResult legacyGameResult = GetGameRedirected(gameId);
  final legacyListRequests = <ListGamesRequest>[];
  final legacyGameIds = <GameId>[];

  @override
  Future<GamePage> listGames(ListGamesRequest request) async {
    legacyListRequests.add(request);
    return legacyPage;
  }

  @override
  Future<LibraryFacets> getLibraryFacets(LibraryFacetQuery request) async =>
      const LibraryFacets(
        platforms: <PlatformFacetBucket>[],
        regions: <RegionFacetBucket>[],
        hydrationStates: <HydrationStateFacetBucket>[],
        availabilityStates: <AvailabilityStateFacetBucket>[],
      );

  @override
  Future<GetGameResult> getGame(GameId gameId) async {
    legacyGameIds.add(gameId);
    return legacyGameResult;
  }
}

final class _RevisionFencedLibraryGatewayFake extends _LibraryGatewayFake
    implements RevisionFencedLibraryGateway {
  _RevisionFencedLibraryGatewayFake(super.id);

  final GamePage revisionPage = const GamePage(
    items: <GameLibraryRow>[],
    nextCursor: 'revision-next',
  );
  final revisionRequests = <ListGamesRequest>[];
  final revisionViewTokens = <String?>[];
  final detailGameIds = <GameId>[];
  final detailViewTokens = <String>[];
  Object? revisionListFailure;
  Object? revisionDetailFailure;

  @override
  Future<RevisionFencedLibraryPage> listGamesRevisionFenced(
    ListGamesRequest request, {
    String? viewToken,
  }) async {
    if (revisionListFailure case final Object error) throw error;
    revisionRequests.add(request);
    revisionViewTokens.add(viewToken);
    return RevisionFencedLibraryPage(
      page: revisionPage,
      viewToken: viewToken ?? 'view-token',
    );
  }

  @override
  Future<GetGameResult> getGameWithView(GameId gameId, String viewToken) async {
    if (revisionDetailFailure case final Object error) throw error;
    detailGameIds.add(gameId);
    detailViewTokens.add(viewToken);
    return legacyGameResult;
  }
}
