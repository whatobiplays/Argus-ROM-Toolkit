import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/application/library_controller.dart';
import 'package:argus/features/library/library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../sources/sources_test_fakes.dart';
import 'library_test_fakes.dart';

void main() {
  test('Library width bands honor every exact contract boundary', () {
    expect(libraryWidthClassForWidth(599), LibraryWidthClass.compact);
    expect(libraryWidthClassForWidth(600), LibraryWidthClass.medium);
    expect(libraryWidthClassForWidth(839), LibraryWidthClass.medium);
    expect(libraryWidthClassForWidth(840), LibraryWidthClass.expanded);
    expect(libraryWidthClassForWidth(1199), LibraryWidthClass.expanded);
    expect(libraryWidthClassForWidth(1200), LibraryWidthClass.large);
  });

  testWidgets('renders bounded rows and compact controls at 2x text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(599, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final reads = FakeLibraryReads();
    reads.onListGames = (_) => GamePage(items: [libraryRow()]);
    final controller = await _readyController(reads);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _libraryHarness(
        controller: controller,
        textScaler: const TextScaler.linear(2),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('library-search')),
      findsOneWidget,
    );
    expect(find.text('Search Library'), findsOneWidget);
    expect(find.text('Test Game'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('library-refresh-selected')),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('grid card controls are not clipped by their Stack', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final reads = FakeLibraryReads()
      ..onListGames = (_) => GamePage(items: [libraryRow()]);
    final controller = await _readyController(reads);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_libraryHarness(controller: controller));
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<Stack>(find.byType(Stack))
          .any((stack) => stack.clipBehavior == Clip.none),
      isTrue,
    );
  });

  for (final viewMode in LibraryViewMode.values) {
    testWidgets(
      'keeps page and row identifiers independent in ${viewMode.name} semantics',
      (tester) async {
        tester.view.physicalSize = const Size(900, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();

        final first = libraryRow(
          id: '11111111111111111111111111111111',
          title: 'Duplicate title',
        );
        final second = libraryRow(
          id: '22222222222222222222222222222222',
          title: 'Duplicate title',
        );
        final reads = FakeLibraryReads()
          ..onListGames = (request) => request.cursor == null
              ? GamePage(items: [first], nextCursor: 'cursor-1')
              : GamePage(items: [second]);
        final controller = await _readyController(reads);
        addTearDown(controller.dispose);
        await controller.loadMore();
        controller.setViewMode(viewMode);

        await tester.pumpWidget(_libraryHarness(controller: controller));
        await tester.pumpAndSettle();

        final firstPage = controller.pageBoundaryForRow(0)!;
        final secondPage = controller.pageBoundaryForRow(1)!;
        final firstRow = controller.rowCorrelationForIndex(0)!;
        final secondRow = controller.rowCorrelationForIndex(1)!;
        expect(firstRow.gameId, first.gameId);
        expect(secondRow.gameId, second.gameId);
        expect(
          firstRow.semanticsIdentifier,
          isNot(secondRow.semanticsIdentifier),
        );
        expect(
          firstPage.semanticsIdentifier,
          isNot(firstRow.semanticsIdentifier),
        );
        expect(
          secondPage.semanticsIdentifier,
          isNot(secondRow.semanticsIdentifier),
        );

        final firstPageFinder = find.bySemanticsIdentifier(
          firstPage.semanticsIdentifier,
        );
        final firstRowFinder = find.bySemanticsIdentifier(
          firstRow.semanticsIdentifier,
        );
        final secondPageFinder = find.bySemanticsIdentifier(
          secondPage.semanticsIdentifier,
        );
        final secondRowFinder = find.bySemanticsIdentifier(
          secondRow.semanticsIdentifier,
        );
        expect(firstPageFinder, findsOneWidget);
        expect(firstRowFinder, findsOneWidget);
        expect(secondPageFinder, findsOneWidget);
        expect(secondRowFinder, findsOneWidget);

        final firstPageNode = tester.getSemantics(firstPageFinder);
        final firstRowNode = tester.getSemantics(firstRowFinder);
        final secondPageNode = tester.getSemantics(secondPageFinder);
        final secondRowNode = tester.getSemantics(secondRowFinder);
        expect(firstPageNode.identifier, firstPage.semanticsIdentifier);
        expect(secondPageNode.identifier, secondPage.semanticsIdentifier);
        expect(firstRowNode.identifier, firstRow.semanticsIdentifier);
        expect(secondRowNode.identifier, secondRow.semanticsIdentifier);
        expect(firstPageNode.id, isNot(firstRowNode.id));
        expect(secondPageNode.id, isNot(secondRowNode.id));
        expect(firstPageNode.label, isEmpty);
        expect(secondPageNode.label, isEmpty);
        expect(firstRowNode.label, startsWith('Duplicate title, '));
        expect(secondRowNode.label, firstRowNode.label);
        semantics.dispose();
      },
    );
  }

  for (final viewMode in LibraryViewMode.values) {
    testWidgets(
      'exposes later page semantics after virtualized ${viewMode.name} scrolling',
      (tester) async {
        tester.view.physicalSize = const Size(900, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();

        final rows = List<GameLibraryRow>.generate(
          52,
          (index) => libraryRow(
            id: (index + 1).toRadixString(16).padLeft(32, '0'),
            title: 'Game $index',
          ),
        );
        final reads = FakeLibraryReads()
          ..onListGames = (request) => request.cursor == null
              ? GamePage(items: rows.take(50).toList(), nextCursor: 'cursor-1')
              : GamePage(items: rows.skip(50).toList());
        final controller = await _readyController(reads);
        addTearDown(controller.dispose);
        await controller.loadMore();
        controller.setViewMode(viewMode);

        await tester.pumpWidget(_libraryHarness(controller: controller));
        await tester.pumpAndSettle();

        final pageTwo = controller.pageBoundaryForRow(50)!;
        final rowFifty = controller.rowCorrelationForIndex(50)!;
        expect(
          find.bySemanticsIdentifier(pageTwo.semanticsIdentifier),
          findsNothing,
        );
        expect(
          find.bySemanticsIdentifier(rowFifty.semanticsIdentifier),
          findsNothing,
        );

        await tester.drag(
          find.byKey(
            PageStorageKey<String>(
              viewMode == LibraryViewMode.grid
                  ? 'library-game-grid'
                  : 'library-game-list',
            ),
          ),
          const Offset(0, -20000),
        );
        await tester.pumpAndSettle();

        expect(
          find.bySemanticsIdentifier(pageTwo.semanticsIdentifier),
          findsOneWidget,
        );
        expect(
          find.bySemanticsIdentifier(rowFifty.semanticsIdentifier),
          findsOneWidget,
        );
        final builtRows = find.byWidgetPredicate(
          (widget) =>
              widget is Card &&
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'library-game-',
              ),
        );
        expect(
          tester.widgetList<Card>(builtRows).length,
          lessThan(rows.length),
        );
        semantics.dispose();
      },
    );
  }

  testWidgets('first-page loading and failure boundaries are inspectable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();

    final response = Completer<GamePage>();
    final reads = FakeLibraryReads()..onListGames = (_) => response.future;
    final controller = await _readyController(reads, initialize: false);
    addTearDown(controller.dispose);
    final load = controller.initialize();

    await tester.pumpWidget(_libraryHarness(controller: controller));
    await tester.pump();
    final loadingPage = controller.emptyStatePageBoundaries.single;
    expect(loadingPage.pageStatus, LibraryPageStatus.loading);
    expect(loadingPage.expectedRowCount, isNull);
    expect(
      find.bySemanticsIdentifier(loadingPage.semanticsIdentifier),
      findsOneWidget,
    );

    response.completeError(
      libraryApplicationFailure('ARGUS.V1.LIBRARY.READ_FAILED'),
    );
    await load;
    await tester.pumpAndSettle();
    final failedPage = controller.emptyStatePageBoundaries.single;
    expect(failedPage.pageStatus, LibraryPageStatus.failed);
    expect(failedPage.expectedRowCount, isNull);
    expect(
      find.bySemanticsIdentifier(failedPage.semanticsIdentifier),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('continuation loading and failure boundaries preserve rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();

    final first = libraryRow(id: '11111111111111111111111111111111');
    final response = Completer<GamePage>();
    final reads = FakeLibraryReads()
      ..onListGames = (request) => request.cursor == null
          ? GamePage(items: [first], nextCursor: 'cursor-1')
          : response.future;
    final controller = await _readyController(reads);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_libraryHarness(controller: controller));
    await tester.pumpAndSettle();

    final load = controller.loadMore();
    await tester.pump();
    final loadingPage = controller.trailingPageBoundaries.single;
    expect(loadingPage.pageStatus, LibraryPageStatus.loading);
    expect(loadingPage.pageOrdinal, 2);
    expect(loadingPage.expectedRowCount, isNull);
    expect(
      find.bySemanticsIdentifier(loadingPage.semanticsIdentifier),
      findsOneWidget,
    );
    expect(controller.state.games, [first]);

    response.completeError(
      libraryApplicationFailure('ARGUS.V1.LIBRARY.READ_FAILED'),
    );
    await load;
    await tester.pumpAndSettle();
    final failedPage = controller.trailingPageBoundaries.single;
    expect(failedPage.pageStatus, LibraryPageStatus.failed);
    expect(failedPage.observationId, loadingPage.observationId);
    expect(failedPage.pageOrdinal, 2);
    expect(failedPage.expectedRowCount, isNull);
    expect(
      find.bySemanticsIdentifier(failedPage.semanticsIdentifier),
      findsOneWidget,
    );
    expect(controller.state.games, [first]);
    expect(
      controller.rowCorrelationForIndex(0)!.observationId,
      failedPage.observationId,
    );
    semantics.dispose();
  });

  testWidgets('completed empty pages have inspectable, separate boundaries', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();

    final emptyFirstReads = FakeLibraryReads()
      ..onListGames = (_) => const GamePage(items: []);
    final emptyFirstController = await _readyController(emptyFirstReads);
    addTearDown(emptyFirstController.dispose);
    await tester.pumpWidget(_libraryHarness(controller: emptyFirstController));
    await tester.pumpAndSettle();
    final emptyFirst = emptyFirstController.emptyStatePageBoundaries.single;
    expect(emptyFirst.pageStatus, LibraryPageStatus.complete);
    expect(emptyFirst.expectedRowCount, 0);
    expect(
      find.bySemanticsIdentifier(emptyFirst.semanticsIdentifier),
      findsOneWidget,
    );

    final first = libraryRow(id: '11111111111111111111111111111111');
    final terminalReads = FakeLibraryReads()
      ..onListGames = (request) => request.cursor == null
          ? GamePage(items: [first], nextCursor: 'cursor-1')
          : const GamePage(items: []);
    final terminalController = await _readyController(terminalReads);
    addTearDown(terminalController.dispose);
    await terminalController.loadMore();
    await tester.pumpWidget(_libraryHarness(controller: terminalController));
    await tester.pumpAndSettle();
    final terminalPage = terminalController.trailingPageBoundaries.single;
    expect(terminalPage.pageStatus, LibraryPageStatus.complete);
    expect(terminalPage.pageOrdinal, 2);
    expect(terminalPage.expectedRowCount, 0);
    expect(terminalController.rowCorrelationForIndex(1), isNull);
    expect(
      find.bySemanticsIdentifier(terminalPage.semanticsIdentifier),
      findsOneWidget,
    );
    expect(terminalController.state.games, [first]);
    semantics.dispose();
  });

  testWidgets('keeps a 10,000-plus logical library widget-lazy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const totalRows = 10050;
    final rows = List<GameLibraryRow>.generate(
      totalRows,
      (index) => libraryRow(
        id: (index + 1).toRadixString(16).padLeft(32, '0'),
        title: 'Game $index',
      ),
    );
    final reads = FakeLibraryReads()
      ..onListGames = (request) {
        final start = request.cursor == null
            ? 0
            : int.parse(request.cursor!.substring('cursor-'.length));
        final items = rows
            .skip(start)
            .take(LibraryController.pageSize)
            .toList();
        final end = start + items.length;
        return GamePage(
          items: items,
          nextCursor: end < rows.length ? 'cursor-$end' : null,
        );
      };
    final controller = await _readyController(reads);
    addTearDown(controller.dispose);
    for (
      var loaded = LibraryController.pageSize;
      loaded < totalRows;
      loaded += LibraryController.pageSize
    ) {
      await controller.loadMore();
    }
    expect(controller.state.games, hasLength(totalRows));

    await tester.pumpWidget(_libraryHarness(controller: controller));
    await tester.pumpAndSettle();

    final builtRows = find.byWidgetPredicate(
      (widget) =>
          widget is Card &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('library-game-'),
    );
    expect(tester.widgetList<Card>(builtRows).length, lessThan(totalRows));
  });

  testWidgets('library refresh fake failures reach the toolbar error path', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final reads = FakeLibraryReads()
      ..onListGames = (_) => GamePage(items: [libraryRow()]);
    final refresh = FakeLibraryRefreshApi()
      ..failure = const TransportFailure('refresh failed');
    final controller = await _readyController(reads, refreshApi: refresh);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _libraryHarness(controller: controller, refreshApi: refresh),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('library-refresh')));
    await tester.pump();

    expect(find.text('refresh failed'), findsOneWidget);
    expect(refresh.failure, isNull);
  });

  testWidgets(
    'keeps usable rows visible while reconciliation is still loading',
    (tester) async {
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final pendingRefresh = Completer<GamePage>();
      var listCalls = 0;
      final reads = FakeLibraryReads()
        ..onListGames = (_) {
          listCalls++;
          if (listCalls == 1) return GamePage(items: [libraryRow()]);
          return pendingRefresh.future;
        };
      final demands = StreamController<LibraryReconciliationDemand>.broadcast();
      addTearDown(demands.close);
      final controller = await _readyController(
        reads,
        demandSource: LibraryReconciliationDemandSource(demands.stream),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_libraryHarness(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('Test Game'), findsOneWidget);

      demands.add(const LibraryReconciliationDemand.listChanged());
      await tester.pump();
      await tester.pump();

      expect(reads.requests, hasLength(2));
      expect(find.text('Test Game'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      pendingRefresh.complete(
        GamePage(items: [libraryRow(title: 'Updated Game')]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test Game'), findsNothing);
      expect(find.text('Updated Game'), findsOneWidget);
    },
  );
}

Future<LibraryController> _readyController(
  FakeLibraryReads reads, {
  FakeLibraryRefreshApi? refreshApi,
  LibraryReconciliationDemandSource? demandSource,
  bool initialize = true,
}) async {
  final controller = LibraryController(
    reads: reads,
    sources: FakeSourcesApi(),
    refreshApi: refreshApi ?? FakeLibraryRefreshApi(),
    gamesApi: FakeGamesApi(),
    scope: const LibraryScope.platform('nintendo.nes'),
    runtimeContext: readyLibraryRuntimeContext,
    demandSource:
        demandSource ??
        const LibraryReconciliationDemandSource(
          Stream<LibraryReconciliationDemand>.empty(),
        ),
  );
  if (initialize) await controller.initialize();
  return controller;
}

Widget _libraryHarness({
  required LibraryController controller,
  TextScaler? textScaler,
  LibraryRefreshApi? refreshApi,
}) => ProviderScope(
  overrides: [
    libraryControllerProvider(
      controller.state.scope,
    ).overrideWithValue(controller),
    if (refreshApi != null)
      libraryRefreshApiProvider.overrideWithValue(refreshApi),
  ],
  child: MediaQuery(
    data: MediaQueryData(textScaler: textScaler ?? const TextScaler.linear(1)),
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
