import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../sources/sources_test_fakes.dart';
import 'library_test_fakes.dart';

void main() {
  test('range selection is based on loaded GameId order', () async {
    final rows = [
      libraryRow(id: '11111111111111111111111111111111', title: 'One'),
      libraryRow(id: '22222222222222222222222222222222', title: 'Two'),
      libraryRow(id: '33333333333333333333333333333333', title: 'Three'),
    ];
    final reads = FakeLibraryReads()
      ..onListGames = (_) => GamePage(items: rows);
    final controller = await _readyController(reads);
    addTearDown(controller.dispose);

    controller.toggleSelection(rows.first.gameId);
    controller.selectRange(rows.last.gameId);

    expect(
      controller.state.selectedGameIds,
      containsAll(<GameId>[rows[0].gameId, rows[1].gameId, rows[2].gameId]),
    );
    expect(controller.state.selectedGameIds, hasLength(3));
  });

  test('grid and list retain independent presentation scroll offsets', () {
    var state = LibraryState.initial(const LibraryScope.all());
    state = state.copyWith(gridScrollOffset: 120, listScrollOffset: 30);
    expect(state.scrollOffset, 120);

    state = state.copyWith(viewMode: LibraryViewMode.list);
    expect(state.scrollOffset, 30);
    state = state.copyWith(scrollOffset: 75);
    expect(state.listScrollOffset, 75);
    expect(state.gridScrollOffset, 120);
  });

  testWidgets(
    'long press selects a stable GameId, back exits selection, and refreshes stay bounded',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 800);
      addTearDown(tester.view.reset);

      final first = libraryRow(
        id: '11111111111111111111111111111111',
        title: 'First Game',
      );
      final second = libraryRow(
        id: '22222222222222222222222222222222',
        title: 'Second Game',
      );
      final reads = FakeLibraryReads()
        ..onListGames = (_) => GamePage(items: [first, second]);
      final refresh = FakeLibraryRefreshApi();
      final games = FakeGamesApi();
      final controller = await _readyController(
        reads,
        refreshApi: refresh,
        gamesApi: games,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryControllerProvider(
              controller.state.scope,
            ).overrideWithValue(controller),
          ],
          child: MaterialApp(
            home: LibraryPage(
              scope: controller.state.scope,
              onOpenAll: () {},
              onOpenSources: () {},
              onOpenGame: (_) {},
              onOpenJob: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(
        find.byKey(
          const ValueKey<String>(
            'library-game-11111111111111111111111111111111',
          ),
        ),
      );
      await tester.pump();

      expect(controller.state.selectedGameIds, {first.gameId});
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey<String>('library-refresh-selected')),
            )
            .onPressed,
        isNotNull,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('library-refresh-selected')),
      );
      await tester.pump();
      expect(refresh.gameRefreshTargets, [
        [first.gameId],
      ]);
      expect(refresh.gameRefreshModes, [RefreshMode.eligibleOnly]);

      await tester.tap(find.byTooltip('Force refresh this Game').first);
      await tester.pump();
      expect(games.refreshedGameIds, [first.gameId]);
      expect(games.refreshModes, [RefreshMode.force]);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(controller.state.selectedGameIds, isEmpty);
    },
  );
}

Future<LibraryController> _readyController(
  FakeLibraryReads reads, {
  FakeLibraryRefreshApi? refreshApi,
  FakeGamesApi? gamesApi,
}) async {
  final controller = LibraryController(
    reads: reads,
    sources: FakeSourcesApi(),
    refreshApi: refreshApi ?? FakeLibraryRefreshApi(),
    gamesApi: gamesApi ?? FakeGamesApi(),
    scope: const LibraryScope.platform('nintendo.nes'),
    runtimeContext: readyLibraryRuntimeContext,
    demandSource: const LibraryReconciliationDemandSource(
      Stream<LibraryReconciliationDemand>.empty(),
    ),
  );
  await controller.initialize();
  return controller;
}
