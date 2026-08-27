import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/application/library_controller.dart';
import 'package:argus/features/library/application/library_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../sources/sources_test_fakes.dart';
import 'library_test_fakes.dart';

void main() {
  test(
    'loads bounded first and continuation pages with backend facets',
    () async {
      final first = libraryRow(id: '11111111111111111111111111111111');
      final second = libraryRow(id: '22222222222222222222222222222222');
      final reads = FakeLibraryReads(
        facets: const LibraryFacets(
          platforms: [
            PlatformFacetBucket(platformId: PlatformId.nintendoNes, count: 2),
          ],
          regions: [],
          hydrationStates: [],
          availabilityStates: [],
        ),
      );
      reads.onListGames = (request) => request.cursor == null
          ? GamePage(items: [first], nextCursor: 'opaque-next')
          : GamePage(items: [second]);
      final sources = FakeSourcesApi();
      final controller = LibraryController(
        reads: reads,
        sources: sources,
        refreshApi: FakeLibraryRefreshApi(),
        gamesApi: FakeGamesApi(),
        scope: const LibraryScopeAll(),
        runtimeContext: readyLibraryRuntimeContext,
        demandSource: const LibraryReconciliationDemandSource(
          Stream<LibraryReconciliationDemand>.empty(),
        ),
      );

      await controller.initialize();
      expect(controller.state.phase, LibraryLoadPhase.ready);
      expect(controller.state.games, [first]);
      expect(controller.state.facets?.platforms.single.count, 2);
      expect(reads.requests.single.pageSize, LibraryController.pageSize);

      await controller.loadMore();
      expect(controller.state.games, [first, second]);
      expect(reads.requests.last.cursor, 'opaque-next');
      expect(reads.facetRequests, hasLength(1));
      controller.dispose();
    },
  );

  test(
    'sends normalized query changes to the backend instead of filtering locally',
    () async {
      final reads = FakeLibraryReads();
      reads.onListGames = (_) => const GamePage(items: []);
      final controller = _controller(reads: reads);

      await controller.initialize();
      await controller.setFilters(
        const LibraryFilter(
          platformIds: ['nintendo.nes'],
          regions: ['us'],
          hydrationStates: [HydrationState.partiallyHydrated],
          availabilityStates: [AvailabilityState.partiallyUnavailable],
        ),
      );
      await controller.setSort(
        const LibrarySort(
          field: LibrarySortField.releaseDate,
          direction: LibrarySortDirection.descending,
        ),
      );

      final request = reads.requests.last;
      expect(request.pageSize, LibraryController.pageSize);
      expect(request.filters.regions, ['us']);
      expect(request.filters.hydrationStates, [
        HydrationState.partiallyHydrated,
      ]);
      expect(request.sort.field, LibrarySortField.releaseDate);
      expect(request.sort.direction, LibrarySortDirection.descending);
      expect(controller.state.games, isEmpty);
      controller.dispose();
    },
  );

  test(
    'does not publish a late page from an older request generation',
    () async {
      final firstGate = Completer<void>();
      final reads = FakeLibraryReads();
      var calls = 0;
      reads.onListGames = (_) async {
        calls++;
        if (calls == 1) {
          await firstGate.future;
          return GamePage(items: [libraryRow(title: 'Old response')]);
        }
        return GamePage(items: [libraryRow(title: 'New response')]);
      };
      final controller = _controller(reads: reads);

      final initial = controller.initialize();
      await Future<void>.delayed(Duration.zero);
      await controller.setFilters(const LibraryFilter(regions: ['jp']));
      firstGate.complete();
      await initial;
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.games.single.displayTitle, 'New response');
      expect(calls, 2);
      controller.dispose();
    },
  );

  test(
    'selection targets are stable GameIds and bulk refresh is EligibleOnly',
    () async {
      final refresh = FakeLibraryRefreshApi();
      final games = FakeGamesApi();
      final controller = _controller(refreshApi: refresh, gamesApi: games);
      final first = GameId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
      final second = GameId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      controller.toggleSelection(first);
      controller.toggleSelection(second);

      final handle = await controller.refreshSelected();
      expect(handle?.operationType, 'game_refresh');
      expect(refresh.gameRefreshTargets.single, [second, first]);
      expect(refresh.gameRefreshModes.single, RefreshMode.eligibleOnly);

      final forced = await controller.forceRefresh(first);
      expect(forced.operationType, 'game_refresh');
      expect(games.refreshModes, [RefreshMode.force]);
      controller.dispose();
    },
  );

  test('bulk refresh rejects empty and over-bound selections', () async {
    final refresh = FakeLibraryRefreshApi();
    final controller = _controller(refreshApi: refresh);
    expect(await controller.refreshSelected(), isNull);

    for (
      var index = 1;
      index <= LibraryController.maxRefreshSelected + 1;
      index++
    ) {
      final id = index.toRadixString(16).padLeft(32, '0');
      controller.toggleSelection(GameId(id));
    }
    expect(await controller.refreshSelected(), isNull);
    expect(refresh.gameRefreshTargets, isEmpty);
    controller.dispose();
  });
}

LibraryController _controller({
  FakeLibraryReads? reads,
  FakeLibraryRefreshApi? refreshApi,
  FakeGamesApi? gamesApi,
}) {
  final libraryReads = reads ?? FakeLibraryReads();
  libraryReads.onListGames ??= (_) => const GamePage(items: []);
  return LibraryController(
    reads: libraryReads,
    sources: FakeSourcesApi(),
    refreshApi: refreshApi ?? FakeLibraryRefreshApi(),
    gamesApi: gamesApi ?? FakeGamesApi(),
    scope: const LibraryScope.platform('nintendo.nes'),
    runtimeContext: readyLibraryRuntimeContext,
    demandSource: const LibraryReconciliationDemandSource(
      Stream<LibraryReconciliationDemand>.empty(),
    ),
  );
}
