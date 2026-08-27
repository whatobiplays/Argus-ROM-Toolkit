import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/application/game_detail_controller.dart';
import 'package:argus/features/library/application/library_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'library_test_fakes.dart';

void main() {
  test('loads found detail and keeps the routed GameId', () async {
    final games = FakeGamesApi()
      ..result = GetGameFound(gameDetail(metadata: resolvedMetadata()));
    final controller = GameDetailController(
      games: games,
      gameId: const GameId('11111111111111111111111111111111'),
      runtimeContext: readyLibraryRuntimeContext,
    );

    await controller.initialize();

    expect(controller.state.phase, GameDetailLoadPhase.ready);
    expect(
      controller.state.detail?.resolvedMetadata?.displayTitle,
      'Resolved Test Game',
    );
    expect(games.requestedGameIds, [controller.state.requestedGameId]);
    controller.dispose();
  });

  test('preserves a redirect as a typed canonical identity', () async {
    final canonical = const GameId('22222222222222222222222222222222');
    final games = FakeGamesApi()..result = GetGameRedirected(canonical);
    final controller = GameDetailController(
      games: games,
      gameId: const GameId('11111111111111111111111111111111'),
      runtimeContext: readyLibraryRuntimeContext,
    );

    await controller.initialize();

    expect(controller.state.phase, GameDetailLoadPhase.redirected);
    expect(controller.state.canonicalGameId, canonical);
    controller.dispose();
  });

  test(
    'maps the published not-found application error to missing state',
    () async {
      final games = FakeGamesApi()..getFailure = gameNotFoundFailure();
      final controller = GameDetailController(
        games: games,
        gameId: const GameId('11111111111111111111111111111111'),
        runtimeContext: readyLibraryRuntimeContext,
      );

      await controller.initialize();

      expect(controller.state.phase, GameDetailLoadPhase.missing);
      expect(controller.state.detail, isNull);
      controller.dispose();
    },
  );

  test(
    'retains inactive-orphan detail as a ready read-only projection',
    () async {
      final detail = gameDetail(lifecycle: GameLifecycle.inactiveOrphan);
      final games = FakeGamesApi()..result = GetGameFound(detail);
      final controller = GameDetailController(
        games: games,
        gameId: detail.gameId,
        runtimeContext: readyLibraryRuntimeContext,
      );

      await controller.initialize();

      expect(controller.state.phase, GameDetailLoadPhase.ready);
      expect(controller.state.detail?.lifecycle, GameLifecycle.inactiveOrphan);
      expect(
        controller.state.detail?.availabilityState,
        AvailabilityState.inactiveOrphan,
      );
      controller.dispose();
    },
  );

  test('does not read before runtime readiness', () async {
    final games = FakeGamesApi();
    final controller = GameDetailController(
      games: games,
      gameId: const GameId('11111111111111111111111111111111'),
      runtimeContext: const LibraryRuntimeContextPreReady(),
    );

    await controller.initialize();

    expect(controller.state.phase, GameDetailLoadPhase.preReady);
    expect(games.requestedGameIds, isEmpty);
    controller.dispose();
  });

  test('refresh actions retain their focused single-Game mode', () async {
    final games = FakeGamesApi();
    final controller = GameDetailController(
      games: games,
      gameId: const GameId('11111111111111111111111111111111'),
      runtimeContext: readyLibraryRuntimeContext,
    );

    await controller.refresh(RefreshMode.eligibleOnly);
    await controller.refresh(RefreshMode.force);

    expect(games.refreshedGameIds, [
      controller.state.requestedGameId,
      controller.state.requestedGameId,
    ]);
    expect(games.refreshModes, [RefreshMode.eligibleOnly, RefreshMode.force]);
    controller.dispose();
  });

  test('artwork cache deduplicates, bounds, and retries failures', () async {
    final api = FakeArtworkApi();
    final first = const ArtworkAssetBytes(
      assetId: 'asset-a',
      bytes: [1, 2, 3],
      mimeType: 'image/png',
      width: 1,
      height: 1,
    );
    api.assets['asset-a'] = first;
    final cache = ArtworkBytesCache(api: api, maxEntries: 1);

    final one = cache.load('asset-a');
    final two = cache.load('asset-a');
    expect(identical(one, two), isTrue);
    expect(await one, first);
    expect(api.callsByAsset['asset-a'], 1);

    api.failures['asset-missing'] = const TransportFailure('missing');
    await expectLater(
      cache.load('asset-missing'),
      throwsA(isA<TransportFailure>()),
    );
    api.assets['asset-missing'] = const ArtworkAssetBytes(
      assetId: 'asset-missing',
      bytes: [4],
      mimeType: 'image/png',
      width: 1,
      height: 1,
    );
    await cache.load('asset-missing');
    expect(api.callsByAsset['asset-missing'], 2);
    expect(cache.length, 1);
    cache.clear();
  });

  test('artwork cache rejects a response for another asset identity', () async {
    final api = FakeArtworkApi()
      ..assets['asset-a'] = const ArtworkAssetBytes(
        assetId: 'asset-b',
        bytes: [1],
        mimeType: 'image/png',
        width: 1,
        height: 1,
      );
    final cache = ArtworkBytesCache(api: api);

    await expectLater(
      cache.load('asset-a'),
      throwsA(
        isA<TransportFailure>().having(
          (failure) => failure.kind,
          'kind',
          TransportFailureKind.contractMismatch,
        ),
      ),
    );
    expect(cache.length, 0);
  });
}
