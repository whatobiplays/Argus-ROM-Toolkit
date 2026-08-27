import 'dart:async';

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
      demandSource: _emptyDemandSource,
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
      demandSource: _emptyDemandSource,
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
        demandSource: _emptyDemandSource,
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
        demandSource: _emptyDemandSource,
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
      demandSource: _emptyDemandSource,
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
      demandSource: _emptyDemandSource,
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

  test(
    'reconciles matching Library demands while retaining loaded detail',
    () async {
      final demands = StreamController<LibraryReconciliationDemand>.broadcast();
      addTearDown(demands.close);
      const gameId = GameId('11111111111111111111111111111111');
      final initial = gameDetail(id: gameId.value, title: 'Initial detail');
      final updated = gameDetail(id: gameId.value, title: 'Updated detail');
      final secondResult = Completer<GetGameResult>();
      var calls = 0;
      final games = FakeGamesApi()
        ..onGetGame = (_) {
          calls++;
          if (calls == 1) return GetGameFound(initial);
          if (calls == 2) return secondResult.future;
          return GetGameFound(updated);
        };
      final controller = GameDetailController(
        games: games,
        gameId: gameId,
        runtimeContext: readyLibraryRuntimeContext,
        demandSource: LibraryReconciliationDemandSource(demands.stream),
      );

      await controller.initialize();
      demands.add(const LibraryReconciliationDemand.listChanged());
      await Future<void>.delayed(Duration.zero);

      expect(calls, 2);
      expect(controller.state.phase, GameDetailLoadPhase.ready);
      expect(controller.state.detail, initial);
      expect(controller.state.refreshing, isTrue);

      demands.add(
        const LibraryReconciliationDemand.detailChanged(
          gameId: GameId('22222222222222222222222222222222'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);

      secondResult.complete(GetGameFound(updated));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.detail, updated);
      expect(controller.state.refreshing, isFalse);

      demands.add(
        const LibraryReconciliationDemand.detailChanged(gameId: gameId),
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, 3);
      expect(controller.state.detail, updated);
      controller.dispose();
    },
  );

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

const _emptyDemandSource = LibraryReconciliationDemandSource(
  Stream<LibraryReconciliationDemand>.empty(),
);
