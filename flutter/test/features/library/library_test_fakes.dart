import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/application/library_state.dart';

/// Deterministic Library read fake that records every bounded request.
final class FakeLibraryReads implements LibraryReads {
  FakeLibraryReads({
    this.facets = const LibraryFacets(
      platforms: [],
      regions: [],
      hydrationStates: [],
      availabilityStates: [],
    ),
  });

  final List<ListGamesRequest> requests = [];
  final List<LibraryFacetQuery> facetRequests = [];
  LibraryFacets facets;
  FutureOr<GamePage> Function(ListGamesRequest request)? onListGames;
  GetGameResult Function(GameId gameId)? onGetGame;
  Object? listFailure;
  Object? facetsFailure;
  Object? detailFailure;

  @override
  Future<GamePage> listGames(ListGamesRequest request) async {
    requests.add(request);
    final failure = listFailure;
    if (failure != null) {
      listFailure = null;
      throw failure;
    }
    final handler = onListGames;
    if (handler != null) return await handler(request);
    return const GamePage(items: []);
  }

  @override
  Future<LibraryFacets> getLibraryFacets(LibraryFacetQuery request) async {
    facetRequests.add(request);
    final failure = facetsFailure;
    if (failure != null) {
      facetsFailure = null;
      throw failure;
    }
    return facets;
  }

  @override
  Future<GetGameResult> getGame(GameId gameId) async {
    final failure = detailFailure;
    if (failure != null) {
      detailFailure = null;
      throw failure;
    }
    final handler = onGetGame;
    if (handler != null) return handler(gameId);
    throw gameNotFoundFailure();
  }
}

/// Deterministic refresh-admission fake for the bounded bulk contract.
final class FakeLibraryRefreshApi implements LibraryRefreshApi {
  final List<List<GameId>> gameRefreshTargets = [];
  final List<RefreshMode> gameRefreshModes = [];
  int libraryRefreshCalls = 0;
  Object? failure;

  @override
  Future<OperationHandle> startGameRefresh({
    required List<GameId> gameIds,
    required RefreshMode mode,
  }) async {
    gameRefreshTargets.add(List.unmodifiable(gameIds));
    gameRefreshModes.add(mode);
    final currentFailure = failure;
    if (currentFailure != null) {
      failure = null;
      throw currentFailure;
    }
    return const OperationHandle(
      jobRunId: JobRunId('11111111111111111111111111111111'),
      operationType: 'game_refresh',
    );
  }

  @override
  Future<OperationHandle> refreshLibrary() async {
    libraryRefreshCalls++;
    final currentFailure = failure;
    if (currentFailure != null) {
      failure = null;
      throw currentFailure;
    }
    return const OperationHandle(
      jobRunId: JobRunId('22222222222222222222222222222222'),
      operationType: 'library_refresh',
    );
  }
}

/// Deterministic single-Game read/refresh fake for detail tests.
final class FakeGamesApi implements GamesApi {
  GetGameResult? result;
  FutureOr<GetGameResult> Function(GameId gameId)? onGetGame;
  Object? getFailure;
  Object? refreshFailure;
  final List<GameId> requestedGameIds = [];
  final List<GameId> refreshedGameIds = [];
  final List<RefreshMode> refreshModes = [];

  @override
  Future<GetGameResult> getGame(GameId gameId) async {
    requestedGameIds.add(gameId);
    final failure = getFailure;
    if (failure != null) {
      getFailure = null;
      throw failure;
    }
    final handler = onGetGame;
    if (handler != null) return await handler(gameId);
    final value = result;
    if (value != null) return value;
    throw gameNotFoundFailure();
  }

  @override
  Future<OperationHandle> refreshGame({
    required GameId gameId,
    required RefreshMode mode,
  }) async {
    refreshedGameIds.add(gameId);
    refreshModes.add(mode);
    final failure = refreshFailure;
    if (failure != null) {
      refreshFailure = null;
      throw failure;
    }
    return const OperationHandle(
      jobRunId: JobRunId('33333333333333333333333333333333'),
      operationType: 'game_refresh',
    );
  }
}

/// Deterministic artwork-byte fake used to prove cache deduplication.
final class FakeArtworkApi implements ArtworkApi {
  final Map<String, ArtworkAssetBytes> assets = {};
  final Map<String, int> callsByAsset = {};
  final Map<String, Object> failures = {};

  @override
  Future<ArtworkAssetBytes> getArtworkAssetBytes(String assetId) async {
    callsByAsset[assetId] = (callsByAsset[assetId] ?? 0) + 1;
    final failure = failures.remove(assetId);
    if (failure != null) throw failure;
    final value = assets[assetId];
    if (value == null) throw const TransportFailure('Artwork asset missing');
    return value;
  }
}

const readyLibraryRuntimeContext = LibraryRuntimeContext.ready(
  runtimeInstanceId: RuntimeInstanceId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
);

GameLibraryRow libraryRow({
  String id = '11111111111111111111111111111111',
  String title = 'Test Game',
  PlatformId platform = PlatformId.nintendoNes,
  HydrationState hydration = HydrationState.hydrated,
  AvailabilityState availability = AvailabilityState.available,
}) => GameLibraryRow(
  gameId: GameId(id),
  displayTitle: title,
  platformId: platform,
  hydrationState: hydration,
  contentCount: 1,
  sourceCount: 1,
  availabilityState: availability,
  updatedAtMs: 1,
);

GameDetail gameDetail({
  String id = '11111111111111111111111111111111',
  String title = 'Test Game',
  GameLifecycle lifecycle = GameLifecycle.active,
  ResolvedMetadata? metadata,
  List<ResolvedArtwork> artwork = const [],
  List<ContentSummary> content = const [],
  List<GameMembershipSummary> memberships = const [],
}) => GameDetail(
  gameId: GameId(id),
  platformId: PlatformId.nintendoNes,
  lifecycle: lifecycle,
  hydrationState: HydrationState.hydrated,
  fallbackTitle: title,
  memberships: memberships,
  content: content,
  availabilityState: lifecycle == GameLifecycle.inactiveOrphan
      ? AvailabilityState.inactiveOrphan
      : AvailabilityState.available,
  resolvedMetadata: metadata,
  resolvedArtwork: artwork,
);

ResolvedMetadata resolvedMetadata({String title = 'Resolved Test Game'}) =>
    ResolvedMetadata(
      displayTitle: title,
      sortTitle: title,
      description: 'A deterministic test description.',
      releaseDate: '1990-01-01',
      developers: const ['Test Studio'],
      publishers: const ['Test Publisher'],
      genres: const ['Action'],
      presentationRegion: 'us',
      presentationLanguages: const ['en'],
      fieldProvenance: const [],
      resolutionRevision: 1,
      resolvedAt: 1,
      providerId: 'test-provider',
    );

ResolvedArtwork resolvedArtwork({
  String assetId = 'asset-cover',
  String type = 'cover_front',
}) => ResolvedArtwork(
  artworkType: type,
  referenceId: 'safe-reference',
  assetId: assetId,
  ordering: 0,
  selectionReason: 'deterministic test selection',
  resolutionRevision: 1,
  resolvedAt: 1,
);

ApplicationFailure gameNotFoundFailure() => ApplicationFailure(
  ClientApplicationError(
    code: ErrorCode('ARGUS.V1.CONFIGURATION.GAME_NOT_FOUND'),
    category: ErrorCategory.configuration,
    severity: ApplicationSeverity.warning,
    recoverability: Recoverability.userAction,
    retryPolicy: RetryPolicy.never,
    messageKey: MessageKey('errors.library.game_not_found'),
    traceId: const TraceId('44444444444444444444444444444444'),
    safeContext: const [],
  ),
);
