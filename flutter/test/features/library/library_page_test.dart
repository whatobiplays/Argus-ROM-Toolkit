import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/application/library_controller.dart';
import 'package:argus/features/library/library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

  testWidgets(
    'Reset All Active is an accessible action only on the All scope',
    (tester) async {
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();

      final allController = await _readyController(
        FakeLibraryReads(),
        scope: const LibraryScopeAll(),
      );
      addTearDown(allController.dispose);
      await tester.pumpWidget(_libraryHarness(controller: allController));
      await tester.pumpAndSettle();

      final action = find.byKey(
        const ValueKey<String>('library-reset-all-active'),
      );
      expect(action, findsOneWidget);
      final actionSemantics = tester.getSemantics(action).getSemanticsData();
      expect(actionSemantics.label, 'Reset All Active');
      expect(actionSemantics.flagsCollection.isButton, isTrue);
      expect(actionSemantics.hasAction(SemanticsAction.tap), isTrue);
      expect(actionSemantics.flagsCollection.isEnabled, Tristate.isTrue);

      final platformController = await _readyController(FakeLibraryReads());
      addTearDown(platformController.dispose);
      await tester.pumpWidget(_libraryHarness(controller: platformController));
      await tester.pumpAndSettle();
      expect(action, findsNothing);

      final preReadyController = LibraryController.preReady(
        scope: const LibraryScopeAll(),
        runtimeContext: const LibraryRuntimeContext.preReady(),
        demandSource: const LibraryReconciliationDemandSource(
          Stream<LibraryReconciliationDemand>.empty(),
        ),
      );
      addTearDown(preReadyController.dispose);
      await tester.pumpWidget(_libraryHarness(controller: preReadyController));
      await tester.pumpAndSettle();
      expect(action, findsOneWidget);
      expect(tester.widget<OutlinedButton>(action).onPressed, isNull);
      final disabledSemantics = tester.getSemantics(action).getSemanticsData();
      expect(disabledSemantics.flagsCollection.isButton, isTrue);
      expect(disabledSemantics.flagsCollection.isEnabled, Tristate.isFalse);
      semantics.dispose();
    },
  );

  testWidgets(
    'reset restores the canonical query without launching a Library refresh',
    (tester) async {
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final first = libraryRow(id: '11111111111111111111111111111111');
      final reads = FakeLibraryReads()
        ..onListGames = (_) => GamePage(items: [first]);
      final refresh = FakeLibraryRefreshApi();
      final controller = await _readyController(
        reads,
        refreshApi: refresh,
        scope: const LibraryScopeAll(),
        searchDebounce: const Duration(days: 1),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _libraryHarness(controller: controller, refreshApi: refresh),
      );
      await tester.pumpAndSettle();

      controller.toggleSelection(first.gameId);
      controller.setScrollOffset(120);
      controller.setViewMode(LibraryViewMode.list);
      controller.setScrollOffset(320);
      await controller.setFilters(const LibraryFilter(regions: ['us']));
      await controller.setSort(
        const LibrarySort(
          field: LibrarySortField.platform,
          direction: LibrarySortDirection.descending,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('library-search')),
        'incidental search',
      );
      await tester.pump();
      expect(controller.state.searchText, 'incidental search');
      expect(controller.state.selectedGameIds, {first.gameId});

      final priorRequestCount = reads.requests.length;
      await tester.tap(
        find.byKey(const ValueKey<String>('library-reset-all-active')),
      );
      await tester.pumpAndSettle();

      expect(controller.state.searchText, isNull);
      expect(controller.state.filters, const LibraryFilter());
      expect(controller.state.sort, const LibrarySort());
      expect(controller.state.viewMode, LibraryViewMode.list);
      expect(controller.state.selectedGameIds, isEmpty);
      expect(controller.state.gridScrollOffset, 0);
      expect(controller.state.listScrollOffset, 0);
      expect(reads.requests, hasLength(priorRequestCount + 1));
      final baselineRequest = reads.requests.last;
      expect(baselineRequest.scope, isA<LibraryScopeAll>());
      expect(baselineRequest.searchText, isNull);
      expect(baselineRequest.filters, const LibraryFilter());
      expect(baselineRequest.sort, const LibrarySort());
      expect(baselineRequest.pageSize, 50);
      expect(
        baselineRequest.viewConsistency,
        LibraryViewConsistency.revisionFenced,
      );
      expect(baselineRequest.cursor, isNull);
      expect(baselineRequest.libraryViewToken, isNull);
      expect(
        controller.pageBoundaryForRow(0)!.queryProfile,
        'AllActiveMembershipBaseline',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey<String>('library-search')),
            )
            .controller
            ?.text,
        isEmpty,
      );
      expect(find.byType(GridView), findsNothing);
      expect(refresh.libraryRefreshCalls, 0);
      expect(refresh.gameRefreshTargets, isEmpty);

      await tester.pump(const Duration(days: 1));
      expect(reads.requests, hasLength(priorRequestCount + 1));
    },
  );

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

        final scrollable = viewMode == LibraryViewMode.grid
            ? find.byType(GridView)
            : find.byWidgetPredicate(
                (widget) => widget is ListView && widget.controller != null,
              );
        await tester.drag(scrollable, const Offset(0, -20000));
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

    final acceptedRowIdentifier = controller
        .rowCorrelationForIndex(0)!
        .semanticsIdentifier;
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

    for (var attempt = 0; attempt < 3; attempt++) {
      await controller.loadMore();
    }
    await tester.pumpAndSettle();
    expect(reads.requests, hasLength(2));
    expect(
      controller.rowCorrelationForIndex(0)!.semanticsIdentifier,
      acceptedRowIdentifier,
    );
    expect(
      controller.trailingPageBoundaries.single.semanticsIdentifier,
      failedPage.semanticsIdentifier,
    );
    expect(
      find.bySemanticsIdentifier(failedPage.semanticsIdentifier),
      findsOneWidget,
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

  testWidgets(
    'StaleView continuation keeps old failure and fresh loading semantics separate',
    (tester) async {
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();

      final first = libraryRow(id: '11111111111111111111111111111111');
      final refreshed = libraryRow(id: '22222222222222222222222222222222');
      final recoveryResponse = Completer<GamePage>();
      final recoveryStarted = Completer<void>();
      final recovered = Completer<void>();
      var firstPageRequests = 0;
      late final FakeLibraryReads reads;
      reads = FakeLibraryReads()
        ..onListGames = (request) {
          if (request.cursor != null) {
            throw libraryApplicationFailure('ARGUS.V1.LIBRARY.STALE_VIEW');
          }
          firstPageRequests++;
          if (firstPageRequests == 1) {
            return GamePage(items: [first], nextCursor: 'cursor-1');
          }
          if (firstPageRequests == 2) {
            recoveryStarted.complete();
            return recoveryResponse.future;
          }
          return GamePage(items: [refreshed]);
        };
      final controller = await _readyController(reads);
      addTearDown(controller.dispose);
      controller.addListener(() {
        if (controller.state.games.any(
              (row) => row.gameId == refreshed.gameId,
            ) &&
            !recovered.isCompleted) {
          recovered.complete();
        }
      });

      await tester.pumpWidget(_libraryHarness(controller: controller));
      await tester.pumpAndSettle();
      final acceptedRow = controller.rowCorrelationForIndex(0)!;
      final load = controller.loadMore();
      await load;
      await recoveryStarted.future;
      await tester.pump();

      expect(controller.state.games, [first]);
      expect(
        controller.rowCorrelationForIndex(0)!.semanticsIdentifier,
        acceptedRow.semanticsIdentifier,
      );
      final boundaries = controller.trailingPageBoundaries;
      expect(boundaries, hasLength(2));
      expect(boundaries.map((page) => page.pageStatus), [
        LibraryPageStatus.failed,
        LibraryPageStatus.loading,
      ]);
      expect(boundaries.first.observationId, acceptedRow.observationId);
      expect(boundaries.first.pageOrdinal, 2);
      expect(boundaries.last.observationId, isNot(acceptedRow.observationId));
      for (final boundary in boundaries) {
        expect(
          find.bySemanticsIdentifier(boundary.semanticsIdentifier),
          findsOneWidget,
        );
        expect(
          tester
              .getSemantics(
                find.bySemanticsIdentifier(boundary.semanticsIdentifier),
              )
              .identifier,
          boundary.semanticsIdentifier,
        );
      }
      expect(
        find.bySemanticsIdentifier(acceptedRow.semanticsIdentifier),
        findsOneWidget,
      );

      recoveryResponse.complete(GamePage(items: [refreshed]));
      await recovered.future;
      await tester.pumpAndSettle();
      final refreshedRow = controller.rowCorrelationForIndex(0)!;
      expect(refreshedRow.observationId, isNot(acceptedRow.observationId));
      expect(
        find.bySemanticsIdentifier(acceptedRow.semanticsIdentifier),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier(refreshedRow.semanticsIdentifier),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets('keeps 10,000-plus baseline rows lazy in Grid and List', (
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
    final controller = await _readyController(
      reads,
      scope: const LibraryScopeAll(),
      sourcesApi: FakeSourcesApi(roots: [fakeRoot()]),
    );
    addTearDown(controller.dispose);
    await controller.resetAllActive();
    for (
      var loaded = LibraryController.pageSize;
      loaded < totalRows;
      loaded += LibraryController.pageSize
    ) {
      await controller.loadMore();
    }
    expect(controller.state.games, hasLength(totalRows));

    final semantics = tester.ensureSemantics();
    for (final viewMode in LibraryViewMode.values) {
      controller.setViewMode(viewMode);
      await tester.pumpWidget(_libraryHarness(controller: controller));
      await tester.pumpAndSettle();

      final builtRows = find.byWidgetPredicate(
        (widget) =>
            widget is Card &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('library-game-'),
      );
      expect(tester.widgetList<Card>(builtRows).length, lessThan(totalRows));
      expect(
        find.byType(GridView),
        viewMode == LibraryViewMode.grid ? findsOneWidget : findsNothing,
      );
      expect(
        controller.pageBoundaryForRow(0)!.queryProfile,
        'AllActiveMembershipBaseline',
      );
      final firstPage = controller.pageBoundaryForRow(0)!;
      final lastRow = controller.rowCorrelationForIndex(totalRows - 1)!;
      expect(lastRow.gameId, rows.last.gameId);
      expect(lastRow.pageOrdinal, 201);
      expect(lastRow.rowOrdinalWithinPage, 50);
      expect(
        find.bySemanticsIdentifier(firstPage.semanticsIdentifier),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(lastRow.semanticsIdentifier),
        findsNothing,
      );
    }
    semantics.dispose();
  });

  testWidgets('Grid and List storage keys use value identities', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final reads = FakeLibraryReads()
      ..onListGames = (_) =>
          GamePage(items: [libraryRow(id: '11111111111111111111111111111111')]);
    final controller = await _readyController(
      reads,
      scope: const LibraryScopeAll(),
      sourcesApi: FakeSourcesApi(roots: [fakeRoot()]),
    );
    addTearDown(controller.dispose);
    controller.setViewMode(LibraryViewMode.grid);
    await tester.pumpWidget(_libraryHarness(controller: controller));
    await tester.pumpAndSettle();

    final gridKey =
        _libraryLayoutStorageKey(tester, LibraryViewMode.grid)
            as PageStorageKey<(String, int, int)>;
    expect(gridKey.value, (
      'grid',
      controller.pageStorageInstanceId,
      controller.scrollResetGeneration,
    ));
    expect(gridKey.value.$1, isA<String>());
    expect(gridKey.value.$2, isA<int>());
    expect(gridKey.value.$3, isA<int>());

    controller.setViewMode(LibraryViewMode.list);
    await tester.pumpAndSettle();
    final listKey =
        _libraryLayoutStorageKey(tester, LibraryViewMode.list)
            as PageStorageKey<(String, int, int)>;
    expect(listKey.value, (
      'list',
      controller.pageStorageInstanceId,
      controller.scrollResetGeneration,
    ));

    await tester.pumpWidget(_libraryHarness(controller: controller));
    await tester.pumpAndSettle();
    expect(_libraryLayoutStorageKey(tester, LibraryViewMode.list), listKey);
    controller.setViewMode(LibraryViewMode.grid);
    await tester.pumpAndSettle();
    expect(_libraryLayoutStorageKey(tester, LibraryViewMode.grid), gridKey);
  });

  testWidgets(
    'Grid and List restore independently and replacement rejects saved offsets',
    (tester) async {
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final rows = List<GameLibraryRow>.generate(
        150,
        (index) => libraryRow(
          id: (index + 1).toRadixString(16).padLeft(32, '0'),
          title: 'Game $index',
        ),
      );
      FakeLibraryReads readsForRows() {
        final reads = FakeLibraryReads();
        reads.onListGames = (request) {
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
        return reads;
      }

      Future<LibraryController> loadedController() async {
        final controller = await _readyController(
          readsForRows(),
          scope: const LibraryScopeAll(),
          sourcesApi: FakeSourcesApi(roots: [fakeRoot()]),
        );
        for (
          var loaded = controller.state.games.length;
          loaded < rows.length;
          loaded += LibraryController.pageSize
        ) {
          await controller.loadMore();
        }
        return controller;
      }

      final first = await loadedController();
      addTearDown(first.dispose);
      expect(first.state.games, hasLength(rows.length));
      first.setViewMode(LibraryViewMode.grid);
      expect(first.state.viewMode, LibraryViewMode.grid);
      final scope = const LibraryScopeAll();
      final selectedControllerProvider =
          NotifierProvider<_LibraryControllerSelection, LibraryController>(
            () => _LibraryControllerSelection(first),
          );
      final bucket = PageStorageBucket();
      late ProviderContainer providerContainer;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryControllerProvider(
              scope,
            ).overrideWith((ref) => ref.watch(selectedControllerProvider)),
          ],
          child: Builder(
            builder: (context) {
              providerContainer = ProviderScope.containerOf(context);
              return MaterialApp(
                home: PageStorage(
                  bucket: bucket,
                  child: LibraryPage(
                    scope: scope,
                    onOpenAll: () {},
                    onOpenSources: () {},
                    onOpenGame: (_) {},
                    onOpenJob: (_) {},
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        providerContainer.read(libraryControllerProvider(scope)),
        same(first),
      );
      expect(
        providerContainer.read(libraryControllerProvider(scope)).state.games,
        hasLength(rows.length),
      );
      expect(
        providerContainer.read(libraryControllerProvider(scope)).state.viewMode,
        LibraryViewMode.grid,
      );
      expect(
        providerContainer.read(libraryControllerProvider(scope)).state.phase,
        LibraryLoadPhase.ready,
      );
      final pageState = tester.state(find.byType(LibraryPage));
      expect(find.byType(GridView), findsOneWidget);

      final gridController = tester
          .widget<GridView>(find.byType(GridView))
          .controller!;
      gridController.jumpTo(420);
      await tester.pumpAndSettle();
      expect(gridController.offset, 420);
      final oldGridKey = _libraryLayoutStorageKey(tester, LibraryViewMode.grid);

      first.setViewMode(LibraryViewMode.list);
      await tester.pumpAndSettle();
      final listController = tester
          .widget<ListView>(
            find.byWidgetPredicate(
              (widget) => widget is ListView && widget.controller != null,
            ),
          )
          .controller!;
      listController.jumpTo(500);
      await tester.pumpAndSettle();
      expect(listController.offset, 500);
      final oldListKey = _libraryLayoutStorageKey(tester, LibraryViewMode.list);

      first.setViewMode(LibraryViewMode.grid);
      await tester.pumpAndSettle();
      expect(gridController.offset, 420);
      first.setViewMode(LibraryViewMode.list);
      await tester.pumpAndSettle();
      expect(listController.offset, 500);

      final replacement = await loadedController();
      addTearDown(replacement.dispose);
      replacement.setViewMode(LibraryViewMode.list);
      expect(replacement.scrollResetGeneration, first.scrollResetGeneration);
      providerContainer
          .read(selectedControllerProvider.notifier)
          .replace(replacement);
      await tester.pumpAndSettle();

      expect(tester.state(find.byType(LibraryPage)), same(pageState));
      expect(
        _libraryLayoutStorageKey(tester, LibraryViewMode.list),
        isNot(oldListKey),
      );
      expect(listController.offset, 0);

      replacement.setViewMode(LibraryViewMode.grid);
      await tester.pumpAndSettle();
      expect(
        _libraryLayoutStorageKey(tester, LibraryViewMode.grid),
        isNot(oldGridKey),
      );
      expect(gridController.offset, 0);
    },
  );

  testWidgets('reset returns both attached layouts to their first row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final rows = List<GameLibraryRow>.generate(
      150,
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
    final controller = await _readyController(
      reads,
      scope: const LibraryScopeAll(),
      sourcesApi: FakeSourcesApi(roots: [fakeRoot()]),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_libraryHarness(controller: controller));
    await tester.pumpAndSettle();
    final preResetGridKey = tester.widget<GridView>(find.byType(GridView)).key;
    await controller.resetAllActive();
    await tester.pumpAndSettle();

    for (final viewMode in LibraryViewMode.values) {
      controller.setViewMode(viewMode);
      for (
        var loaded = controller.state.games.length;
        loaded < rows.length;
        loaded += LibraryController.pageSize
      ) {
        await controller.loadMore();
      }
      await tester.pumpAndSettle();

      final keyBeforeReset = _libraryLayoutStorageKey(tester, viewMode);

      final scrollController = viewMode == LibraryViewMode.grid
          ? tester.widget<GridView>(find.byType(GridView)).controller!
          : tester
                .widget<ListView>(
                  find.byWidgetPredicate(
                    (widget) => widget is ListView && widget.controller != null,
                  ),
                )
                .controller!;
      scrollController.jumpTo(500);
      await tester.pump();
      expect(scrollController.offset, 500);

      await tester.tap(
        find.byKey(const ValueKey<String>('library-reset-all-active')),
      );
      await tester.pumpAndSettle();

      expect(_libraryLayoutStorageKey(tester, viewMode), isNot(keyBeforeReset));
      expect(controller.state.viewMode, viewMode);
      expect(controller.state.games, hasLength(LibraryController.pageSize));
      expect(controller.state.gridScrollOffset, 0);
      expect(controller.state.listScrollOffset, 0);
      expect(scrollController.hasClients, isTrue);
      expect(scrollController.offset, 0);
    }

    final replacement = await _readyController(
      reads,
      scope: const LibraryScopeAll(),
      sourcesApi: FakeSourcesApi(roots: [fakeRoot()]),
    );
    addTearDown(replacement.dispose);
    await tester.pumpWidget(_libraryHarness(controller: replacement));
    await tester.pumpAndSettle();
    expect(
      tester.widget<GridView>(find.byType(GridView)).key,
      isNot(preResetGridKey),
    );
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
  FakeSourcesApi? sourcesApi,
  LibraryReconciliationDemandSource? demandSource,
  LibraryScope scope = const LibraryScope.platform('nintendo.nes'),
  Duration? searchDebounce,
  bool initialize = true,
}) async {
  final controller = LibraryController(
    reads: reads,
    sources: sourcesApi ?? FakeSourcesApi(),
    refreshApi: refreshApi ?? FakeLibraryRefreshApi(),
    gamesApi: FakeGamesApi(),
    scope: scope,
    runtimeContext: readyLibraryRuntimeContext,
    demandSource:
        demandSource ??
        const LibraryReconciliationDemandSource(
          Stream<LibraryReconciliationDemand>.empty(),
        ),
    searchDebounce: searchDebounce ?? LibraryController.defaultSearchDebounce,
  );
  if (initialize) await controller.initialize();
  return controller;
}

Widget _libraryHarness({
  required LibraryController controller,
  TextScaler? textScaler,
  LibraryRefreshApi? refreshApi,
}) => ProviderScope(
  key: ObjectKey(controller),
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

Key _libraryLayoutStorageKey(WidgetTester tester, LibraryViewMode viewMode) {
  if (viewMode == LibraryViewMode.grid) {
    return tester.widget<GridView>(find.byType(GridView)).key!;
  }
  return tester
      .widget<ListView>(
        find.byWidgetPredicate(
          (widget) => widget is ListView && widget.controller != null,
        ),
      )
      .key!;
}

class _LibraryControllerSelection extends Notifier<LibraryController> {
  _LibraryControllerSelection(this.initialController);

  final LibraryController initialController;

  @override
  LibraryController build() => initialController;

  void replace(LibraryController controller) {
    state = controller;
  }
}
