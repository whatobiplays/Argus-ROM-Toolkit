import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/application/library_controller.dart';
import 'package:argus/features/library/application/library_state.dart';
import 'package:argus/features/library/library_composition.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../sources/sources_test_fakes.dart';
import 'library_test_fakes.dart';

void main() {
  test('page storage identity is stable and increases per controller', () {
    final first = _controller();
    final firstIdentity = first.pageStorageInstanceId;
    final second = _controller();

    expect(first.pageStorageInstanceId, firstIdentity);
    expect(second.pageStorageInstanceId, greaterThan(firstIdentity));

    first.dispose();
    second.dispose();
  });

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
      expect(
        reads.requests.single.viewConsistency,
        LibraryViewConsistency.revisionFenced,
      );
      expect(reads.requests.single.cursor, isNull);
      expect(reads.requests.single.libraryViewToken, isNull);
      final firstPage = controller.pageBoundaryForRow(0)!;
      final firstRow = controller.rowCorrelationForIndex(0)!;
      expect(firstPage.observationId, firstRow.observationId);
      expect(firstPage.queryProfile, 'OrdinaryUserQuery');
      expect(firstPage.pageOrdinal, 1);
      expect(firstPage.isFirstPage, isTrue);
      expect(firstPage.isContinuationPage, isFalse);
      expect(firstPage.pageStatus, LibraryPageStatus.complete);
      expect(firstPage.hasNextPage, isTrue);
      expect(firstPage.isFinalPage, isFalse);
      expect(firstPage.pageSize, LibraryController.pageSize);
      expect(firstPage.expectedRowCount, 1);
      expect(
        firstPage.semanticsIdentifier,
        'argus.library.page.v1;observation=${firstPage.observationId};'
        'profile=OrdinaryUserQuery;page=1;first=true;continuation=false;'
        'status=complete;hasNext=true;final=false;pageSize=50;expectedRows=1',
      );
      expect(firstRow.rowOrdinalWithinPage, 1);
      expect(firstRow.gameId, first.gameId);
      expect(
        firstRow.semanticsIdentifier,
        'argus.library.row.v1;observation=${firstPage.observationId};'
        'page=1;row=1;gameId=${Uri.encodeComponent(first.gameId.value)}',
      );

      await controller.loadMore();
      expect(controller.state.games, [first, second]);
      expect(reads.requests.last.cursor, 'opaque-next');
      expect(
        reads.requests.last.viewConsistency,
        LibraryViewConsistency.revisionFenced,
      );
      expect(reads.requests.last.libraryViewToken, reads.revisionFencedToken);
      final secondPage = controller.pageBoundaryForRow(1)!;
      final secondRow = controller.rowCorrelationForIndex(1)!;
      expect(secondPage.observationId, firstPage.observationId);
      expect(secondPage.pageOrdinal, 2);
      expect(secondPage.isFirstPage, isFalse);
      expect(secondPage.isContinuationPage, isTrue);
      expect(secondPage.pageStatus, LibraryPageStatus.complete);
      expect(secondPage.hasNextPage, isFalse);
      expect(secondPage.isFinalPage, isTrue);
      expect(secondPage.expectedRowCount, 1);
      expect(secondRow.observationId, firstPage.observationId);
      expect(secondRow.rowOrdinalWithinPage, 1);
      expect(secondRow.gameId, second.gameId);
      expect(reads.facetRequests, hasLength(1));
      controller.dispose();
    },
  );

  test('explicit reset selects the exact all-active request profile', () async {
    final ordinary = libraryRow(id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    final first = libraryRow(id: '11111111111111111111111111111111');
    final second = libraryRow(id: '22222222222222222222222222222222');
    final reads = FakeLibraryReads();
    reads.onListGames = (request) {
      if (reads.requests.length == 1) return GamePage(items: [ordinary]);
      if (request.cursor == null) {
        return GamePage(items: [first], nextCursor: 'baseline-cursor');
      }
      return GamePage(items: [second]);
    };
    final controller = _controller(
      reads: reads,
      scope: const LibraryScopeAll(),
    );

    await controller.initialize();
    final ordinaryPage = controller.pageBoundaryForRow(0)!;
    expect(ordinaryPage.queryProfile, 'OrdinaryUserQuery');
    final ordinaryRequest = reads.requests.single;
    expect(ordinaryRequest.scope, isA<LibraryScopeAll>());
    expect(ordinaryRequest.searchText, isNull);
    expect(ordinaryRequest.filters, const LibraryFilter());
    expect(ordinaryRequest.sort, const LibrarySort());

    await controller.resetAllActive();
    final firstRequest = reads.requests.last;
    expect(firstRequest.scope, isA<LibraryScopeAll>());
    expect(firstRequest.searchText, isNull);
    expect(firstRequest.filters, const LibraryFilter());
    expect(firstRequest.sort, const LibrarySort());
    expect(firstRequest.sort.field, LibrarySortField.displayTitle);
    expect(firstRequest.sort.direction, LibrarySortDirection.ascending);
    expect(firstRequest.pageSize, 50);
    expect(firstRequest.viewConsistency, LibraryViewConsistency.revisionFenced);
    expect(firstRequest.cursor, isNull);
    expect(firstRequest.libraryViewToken, isNull);

    final baselinePage = controller.pageBoundaryForRow(0)!;
    expect(baselinePage.queryProfile, 'AllActiveMembershipBaseline');
    expect(baselinePage.observationId, isNot(ordinaryPage.observationId));

    controller.toggleSelection(first.gameId);
    controller.setViewMode(LibraryViewMode.list);
    controller.setScrollOffset(140);
    expect(
      controller.pageBoundaryForRow(0)!.observationId,
      baselinePage.observationId,
    );
    await controller.loadMore();
    final continuationRequest = reads.requests.last;
    expect(continuationRequest.scope, isA<LibraryScopeAll>());
    expect(continuationRequest.searchText, isNull);
    expect(continuationRequest.filters, const LibraryFilter());
    expect(continuationRequest.sort, const LibrarySort());
    expect(continuationRequest.pageSize, 50);
    expect(
      continuationRequest.viewConsistency,
      LibraryViewConsistency.revisionFenced,
    );
    expect(continuationRequest.cursor, 'baseline-cursor');
    expect(continuationRequest.libraryViewToken, reads.revisionFencedToken);
    final continuationPage = controller.pageBoundaryForRow(1)!;
    expect(continuationPage.queryProfile, 'AllActiveMembershipBaseline');
    expect(continuationPage.observationId, baselinePage.observationId);
    expect(continuationPage.pageOrdinal, 2);
    expect(controller.rowCorrelationForIndex(1)!.gameId, second.gameId);

    await controller.refresh();
    expect(
      controller.pageBoundaryForRow(0)!.queryProfile,
      'AllActiveMembershipBaseline',
    );
    expect(
      controller.pageBoundaryForRow(0)!.observationId,
      isNot(baselinePage.observationId),
    );

    await controller.setFilters(const LibraryFilter(regions: ['us']));
    expect(controller.pageBoundaryForRow(0)!.queryProfile, 'OrdinaryUserQuery');
    controller.dispose();
  });

  test('baseline profile follows empty first and terminal pages', () async {
    final first = libraryRow(id: '11111111111111111111111111111111');
    final reads = FakeLibraryReads();
    reads.onListGames = (request) {
      if (reads.requests.length <= 2) return const GamePage(items: []);
      return request.cursor == null
          ? GamePage(items: [first], nextCursor: 'baseline-cursor')
          : const GamePage(items: []);
    };
    final controller = _controller(
      reads: reads,
      scope: const LibraryScopeAll(),
    );

    await controller.initialize();
    expect(
      controller.emptyStatePageBoundaries.single.queryProfile,
      'OrdinaryUserQuery',
    );

    await controller.resetAllActive();
    expect(controller.state.games, isEmpty);
    expect(controller.state.hasMore, isFalse);
    final emptyFirstPage = controller.emptyStatePageBoundaries.single;
    expect(emptyFirstPage.queryProfile, 'AllActiveMembershipBaseline');
    expect(emptyFirstPage.pageOrdinal, 1);
    expect(emptyFirstPage.pageStatus, LibraryPageStatus.complete);
    expect(emptyFirstPage.expectedRowCount, 0);
    expect(emptyFirstPage.isFinalPage, isTrue);

    await controller.resetAllActive();
    await controller.loadMore();
    expect(controller.state.games, [first]);
    expect(controller.state.hasMore, isFalse);
    final emptyTerminalPage = controller.trailingPageBoundaries.single;
    expect(emptyTerminalPage.queryProfile, 'AllActiveMembershipBaseline');
    expect(emptyTerminalPage.pageOrdinal, 2);
    expect(emptyTerminalPage.pageStatus, LibraryPageStatus.complete);
    expect(emptyTerminalPage.expectedRowCount, 0);
    expect(emptyTerminalPage.isFinalPage, isTrue);
    expect(
      emptyTerminalPage.observationId,
      controller.rowCorrelationForIndex(0)!.observationId,
    );
    controller.dispose();
  });

  test(
    'baseline reset clears selection and both scroll states while fencing in-flight pages',
    () async {
      final first = libraryRow(id: '11111111111111111111111111111111');
      final second = libraryRow(id: '22222222222222222222222222222222');
      final filteredResponse = Completer<GamePage>();
      final baselineResponse = Completer<GamePage>();
      final baselineRequestStarted = Completer<void>();
      final reads = FakeLibraryReads();
      reads.onListGames = (request) {
        if (reads.requests.length == 1) return GamePage(items: [first, second]);
        if (request.filters.regions.contains('us')) {
          return filteredResponse.future;
        }
        if (!baselineRequestStarted.isCompleted) {
          baselineRequestStarted.complete();
        }
        return baselineResponse.future;
      };
      final controller = _controller(
        reads: reads,
        scope: const LibraryScopeAll(),
        searchDebounce: const Duration(days: 1),
      );
      await controller.initialize();

      controller.toggleSelection(first.gameId);
      controller.setScrollOffset(125);
      controller.setViewMode(LibraryViewMode.list);
      controller.setScrollOffset(425);
      final priorGeneration = controller.scrollResetGeneration;
      final filteredLoad = controller.setFilters(
        const LibraryFilter(regions: ['us']),
      );
      expect(reads.requests, hasLength(2));
      controller.setSearchText('pending search');

      await controller.resetAllActive();
      expect(controller.state.searchText, isNull);
      expect(controller.state.filters, const LibraryFilter());
      expect(controller.state.sort, const LibrarySort());
      expect(controller.state.games, isEmpty);
      expect(controller.state.nextCursor, isNull);
      expect(controller.state.hasMore, isFalse);
      expect(controller.state.selectedGameIds, isEmpty);
      expect(controller.state.viewMode, LibraryViewMode.list);
      expect(controller.state.gridScrollOffset, 0);
      expect(controller.state.listScrollOffset, 0);
      expect(controller.scrollResetGeneration, priorGeneration + 1);
      expect(reads.requests, hasLength(2));

      final baselinePage = Completer<void>();
      controller.addListener(() {
        if (controller.state.phase == LibraryLoadPhase.ready &&
            controller.state.games.length == 2 &&
            controller.pageBoundaryForRow(0)?.queryProfile ==
                'AllActiveMembershipBaseline' &&
            !baselinePage.isCompleted) {
          baselinePage.complete();
        }
      });
      filteredResponse.complete(
        GamePage(items: [first, second], nextCursor: 'late-filter-cursor'),
      );
      await baselineRequestStarted.future;
      expect(reads.requests, hasLength(3));
      expect(controller.state.games, isEmpty);
      expect(
        controller.emptyStatePageBoundaries.single.queryProfile,
        'AllActiveMembershipBaseline',
      );

      baselineResponse.complete(GamePage(items: [first, second]));
      await baselinePage.future;
      await filteredLoad;
      expect(controller.state.games, [first, second]);
      controller.selectRange(second.gameId);
      expect(controller.state.selectedGameIds, {second.gameId});
      controller.dispose();
    },
  );

  test(
    'baseline profile follows stale recovery and failed continuation pages',
    () async {
      final oldRow = libraryRow(id: '11111111111111111111111111111111');
      final newRow = libraryRow(id: '22222222222222222222222222222222');
      final recoveredPage = Completer<void>();
      final reads = FakeLibraryReads();
      reads.onListGames = (request) {
        switch (reads.requests.length) {
          case 1:
            return const GamePage(items: []);
          case 2:
            return GamePage(items: [oldRow], nextCursor: 'stale-cursor');
          case 3:
            throw libraryApplicationFailure('ARGUS.V1.LIBRARY.STALE_VIEW');
          case 4:
            return GamePage(items: [newRow], nextCursor: 'retry-cursor');
          case 5:
            throw const TransportFailure('continuation failed');
          default:
            throw StateError('Unexpected Library request');
        }
      };
      final controller = _controller(
        reads: reads,
        scope: const LibraryScopeAll(),
      );
      await controller.initialize();
      await controller.resetAllActive();
      final oldObservation = controller.pageBoundaryForRow(0)!.observationId;
      controller.addListener(() {
        if (controller.state.phase == LibraryLoadPhase.ready &&
            controller.state.games.length == 1 &&
            controller.state.games.single.gameId == newRow.gameId &&
            !recoveredPage.isCompleted) {
          recoveredPage.complete();
        }
      });

      await controller.loadMore();
      await recoveredPage.future;
      expect(controller.state.games, [newRow]);
      final recoveredBoundary = controller.pageBoundaryForRow(0)!;
      expect(recoveredBoundary.queryProfile, 'AllActiveMembershipBaseline');
      expect(recoveredBoundary.observationId, isNot(oldObservation));
      expect(controller.rowCorrelationForIndex(0)!.gameId, newRow.gameId);

      await controller.loadMore();
      final failedBoundary = controller.trailingPageBoundaries.single;
      expect(failedBoundary.queryProfile, 'AllActiveMembershipBaseline');
      expect(failedBoundary.pageOrdinal, 2);
      expect(failedBoundary.pageStatus, LibraryPageStatus.failed);
      expect(reads.requests.last.cursor, 'retry-cursor');
      expect(reads.requests.last.libraryViewToken, reads.revisionFencedToken);
      controller.dispose();
    },
  );

  test(
    'baseline profile remains on both boundaries after repeated stale failure',
    () async {
      final retained = libraryRow(id: '11111111111111111111111111111111');
      final repeatedStale = Completer<void>();
      final reads = FakeLibraryReads();
      reads.onListGames = (_) {
        switch (reads.requests.length) {
          case 1:
            return const GamePage(items: []);
          case 2:
            return GamePage(items: [retained], nextCursor: 'cursor-1');
          case 3:
          case 4:
            throw libraryApplicationFailure('ARGUS.V1.LIBRARY.STALE_VIEW');
          default:
            throw StateError('Unexpected Library request');
        }
      };
      final controller = _controller(
        reads: reads,
        scope: const LibraryScopeAll(),
      );
      await controller.initialize();
      await controller.resetAllActive();
      final acceptedObservation = controller
          .pageBoundaryForRow(0)!
          .observationId;
      controller.addListener(() {
        if (controller.state.lastFailure != null &&
            controller.trailingPageBoundaries.length == 2 &&
            controller.trailingPageBoundaries.every(
              (boundary) => boundary.pageStatus == LibraryPageStatus.failed,
            ) &&
            !repeatedStale.isCompleted) {
          repeatedStale.complete();
        }
      });

      await controller.loadMore();
      await repeatedStale.future;
      final failures = controller.trailingPageBoundaries;
      expect(failures, hasLength(2));
      expect(
        failures.map((failure) => failure.queryProfile),
        everyElement('AllActiveMembershipBaseline'),
      );
      expect(failures.first.observationId, acceptedObservation);
      expect(failures.last.observationId, isNot(acceptedObservation));
      expect(controller.state.games, [retained]);
      expect(
        controller.pageBoundaryForRow(0)!.observationId,
        acceptedObservation,
      );
      controller.dispose();
    },
  );

  test('runtime replacement returns to an ordinary query profile', () async {
    final runtimeState =
        NotifierProvider<LibraryRuntimeContextHolder, LibraryRuntimeContext>(
          LibraryRuntimeContextHolder.new,
        );
    final reads = FakeLibraryReads()
      ..onListGames = (_) => const GamePage(items: []);
    final container = ProviderContainer(
      overrides: [
        libraryRuntimeContextProvider.overrideWith(
          (ref) => ref.watch(runtimeState),
        ),
        libraryApiProvider.overrideWithValue(reads),
        librarySourcesApiProvider.overrideWithValue(FakeSourcesApi()),
        libraryRefreshApiProvider.overrideWithValue(FakeLibraryRefreshApi()),
        libraryGamesApiProvider.overrideWithValue(FakeGamesApi()),
        libraryReconciliationDemandProvider.overrideWithValue(
          const LibraryReconciliationDemandSource(
            Stream<LibraryReconciliationDemand>.empty(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    const scope = LibraryScopeAll();
    final provider = libraryControllerProvider(scope);
    final providerSubscription = container.listen(provider, (_, _) {});
    addTearDown(providerSubscription.close);
    final first = container.read(provider);
    final firstReady = Completer<void>();
    first.addListener(() {
      if (first.state.phase == LibraryLoadPhase.ready &&
          !firstReady.isCompleted) {
        firstReady.complete();
      }
    });
    if (first.state.phase == LibraryLoadPhase.ready) firstReady.complete();
    await firstReady.future;
    await first.resetAllActive();
    expect(
      first.emptyStatePageBoundaries.single.queryProfile,
      'AllActiveMembershipBaseline',
    );

    container
        .read(runtimeState.notifier)
        .replace(
          const LibraryRuntimeContext.ready(
            runtimeInstanceId: RuntimeInstanceId(
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            ),
          ),
        );
    final replacement = container.read(provider);
    expect(identical(replacement, first), isFalse);
    expect(
      replacement.emptyStatePageBoundaries.single.queryProfile,
      'OrdinaryUserQuery',
    );
  });

  test(
    'query shape changes get fresh observations; view mode does not',
    () async {
      final first = libraryRow(id: '11111111111111111111111111111111');
      final reads = FakeLibraryReads()
        ..onListGames = (_) => GamePage(items: [first]);
      final controller = _controller(reads: reads);

      await controller.initialize();
      final firstObservation = controller
          .rowCorrelationForIndex(0)!
          .observationId;
      controller.setViewMode(LibraryViewMode.list);
      expect(
        controller.rowCorrelationForIndex(0)!.observationId,
        firstObservation,
      );
      expect(reads.requests, hasLength(1));

      await controller.setFilters(const LibraryFilter(regions: ['us']));
      final filteredObservation = controller
          .rowCorrelationForIndex(0)!
          .observationId;
      expect(filteredObservation, isNot(firstObservation));

      await controller.setSort(
        const LibrarySort(
          field: LibrarySortField.releaseDate,
          direction: LibrarySortDirection.descending,
        ),
      );
      final sortedObservation = controller
          .rowCorrelationForIndex(0)!
          .observationId;
      expect(sortedObservation, isNot(filteredObservation));
      expect(
        reads.requests.map((request) => request.viewConsistency),
        everyElement(LibraryViewConsistency.revisionFenced),
      );
      expect(
        reads.requests.map((request) => request.libraryViewToken),
        everyElement(isNull),
      );
      controller.dispose();
    },
  );

  test('observation IDs remain distinct across controller instances', () async {
    final firstController = _controller(
      reads: FakeLibraryReads()
        ..onListGames = (_) => GamePage(
          items: [libraryRow(id: '11111111111111111111111111111111')],
        ),
    );
    final secondController = _controller(
      reads: FakeLibraryReads()
        ..onListGames = (_) => GamePage(
          items: [libraryRow(id: '22222222222222222222222222222222')],
        ),
    );

    await firstController.initialize();
    await secondController.initialize();

    expect(
      firstController.rowCorrelationForIndex(0)!.observationId,
      isNot(secondController.rowCorrelationForIndex(0)!.observationId),
    );
    firstController.dispose();
    secondController.dispose();
  });

  test('StaleView restarts once with a fresh observation', () async {
    final first = libraryRow(id: '11111111111111111111111111111111');
    var calls = 0;
    final reads = FakeLibraryReads()
      ..onListGames = (_) {
        calls++;
        if (calls == 1) {
          throw libraryApplicationFailure('ARGUS.V1.LIBRARY.STALE_VIEW');
        }
        return GamePage(items: [first]);
      };
    final controller = _controller(reads: reads);
    final loadingObservations = <String>[];
    final recovered = Completer<void>();
    controller.addListener(() {
      loadingObservations.addAll(
        controller.emptyStatePageBoundaries.map((page) => page.observationId),
      );
      if (controller.state.games.isNotEmpty && !recovered.isCompleted) {
        recovered.complete();
      }
    });

    await controller.initialize();
    await recovered.future;

    expect(reads.requests, hasLength(2));
    expect(reads.requests.every((request) => request.cursor == null), isTrue);
    expect(
      reads.requests.every((request) => request.libraryViewToken == null),
      isTrue,
    );
    expect(loadingObservations.toSet(), hasLength(2));
    expect(
      controller.rowCorrelationForIndex(0)!.observationId,
      isNot(loadingObservations.first),
    );
    expect(controller.state.lastFailure, isNull);
    controller.dispose();
  });

  test(
    'a repeated StaleView stops after the single automatic restart',
    () async {
      final reads = FakeLibraryReads()
        ..onListGames = (_) {
          throw libraryApplicationFailure('ARGUS.V1.LIBRARY.STALE_VIEW');
        };
      final controller = _controller(reads: reads);
      final loadingObservations = <String>[];
      final failed = Completer<void>();
      controller.addListener(() {
        loadingObservations.addAll(
          controller.emptyStatePageBoundaries.map((page) => page.observationId),
        );
        if (reads.requests.length == 2 &&
            controller.state.lastFailure != null &&
            controller.emptyStatePageBoundaries.last.pageStatus ==
                LibraryPageStatus.failed &&
            !failed.isCompleted) {
          failed.complete();
        }
      });

      await controller.initialize();
      await failed.future;

      expect(reads.requests, hasLength(2));
      expect(controller.state.games, isEmpty);
      expect(controller.state.lastFailure, isA<ApplicationFailure>());
      final failedPages = controller.emptyStatePageBoundaries;
      expect(failedPages, hasLength(2));
      expect(
        failedPages.map((page) => page.pageStatus),
        everyElement(LibraryPageStatus.failed),
      );
      expect(failedPages.map((page) => page.pageOrdinal), everyElement(1));
      expect(loadingObservations.toSet(), hasLength(2));
      expect(failedPages.first.observationId, loadingObservations.first);
      expect(failedPages.last.observationId, loadingObservations.last);
      expect(
        failedPages.first.observationId,
        isNot(failedPages.last.observationId),
      );
      controller.dispose();
    },
  );

  test('StaleView can recover a later invalidated observation', () async {
    final first = libraryRow(id: '11111111111111111111111111111111');
    final refreshed = libraryRow(id: '22222222222222222222222222222222');
    final newest = libraryRow(id: '33333333333333333333333333333333');
    final recoveryResponse = Completer<GamePage>();
    final laterRecoveryResponse = Completer<GamePage>();
    var firstPageRequests = 0;
    var continuationRequests = 0;
    final laterRecoveryStarted = Completer<void>();
    final reads = FakeLibraryReads()
      ..onListGames = (request) {
        if (request.cursor != null) {
          continuationRequests++;
          throw libraryApplicationFailure('ARGUS.V1.LIBRARY.STALE_VIEW');
        }
        firstPageRequests++;
        return switch (firstPageRequests) {
          1 => GamePage(items: [first], nextCursor: 'cursor-1'),
          2 => recoveryResponse.future,
          3 => () {
            if (!laterRecoveryStarted.isCompleted) {
              laterRecoveryStarted.complete();
            }
            return laterRecoveryResponse.future;
          }(),
          _ => GamePage(items: [newest]),
        };
      };
    final controller = _controller(reads: reads);
    final recoveryStarted = Completer<void>();
    final recovered = Completer<void>();
    final latestRecovered = Completer<void>();
    controller.addListener(() {
      if (controller.state.refreshing &&
          controller.state.games.any((row) => row.gameId == first.gameId) &&
          !recoveryStarted.isCompleted) {
        recoveryStarted.complete();
      }
      if (controller.state.games.any((row) => row.gameId == refreshed.gameId) &&
          !recovered.isCompleted) {
        recovered.complete();
      }
      if (controller.state.games.any((row) => row.gameId == newest.gameId) &&
          !latestRecovered.isCompleted) {
        latestRecovered.complete();
      }
    });

    await controller.initialize();
    final originalObservation = controller
        .rowCorrelationForIndex(0)!
        .observationId;
    await controller.loadMore();
    await recoveryStarted.future;

    expect(controller.state.games, [first]);
    expect(
      controller.rowCorrelationForIndex(0)!.observationId,
      originalObservation,
    );
    final staleRecoveryBoundaries = controller.trailingPageBoundaries;
    expect(staleRecoveryBoundaries, hasLength(2));
    expect(staleRecoveryBoundaries.map((page) => page.pageStatus), [
      LibraryPageStatus.failed,
      LibraryPageStatus.loading,
    ]);
    expect(staleRecoveryBoundaries.first.observationId, originalObservation);
    expect(staleRecoveryBoundaries.first.pageOrdinal, 2);
    expect(
      staleRecoveryBoundaries.last.observationId,
      isNot(originalObservation),
    );
    expect(staleRecoveryBoundaries.last.pageOrdinal, 1);

    recoveryResponse.complete(
      GamePage(items: [refreshed], nextCursor: 'cursor-2'),
    );
    await recovered.future;

    expect(reads.requests, hasLength(3));
    expect(reads.requests[1].cursor, 'cursor-1');
    expect(reads.requests[1].libraryViewToken, reads.revisionFencedToken);
    expect(reads.requests[2].cursor, isNull);
    expect(reads.requests[2].libraryViewToken, isNull);
    expect(
      reads.requests[2].viewConsistency,
      LibraryViewConsistency.revisionFenced,
    );
    expect(controller.state.games, [refreshed]);
    expect(controller.state.lastFailure, isNull);

    final recoveredObservation = controller
        .rowCorrelationForIndex(0)!
        .observationId;
    await controller.loadMore();
    await laterRecoveryStarted.future;

    expect(controller.state.games, [refreshed]);
    expect(
      controller.rowCorrelationForIndex(0)!.observationId,
      recoveredObservation,
    );
    expect(controller.trailingPageBoundaries.map((page) => page.pageStatus), [
      LibraryPageStatus.failed,
      LibraryPageStatus.loading,
    ]);
    laterRecoveryResponse.complete(GamePage(items: [newest]));
    await latestRecovered.future;

    expect(reads.requests, hasLength(5));
    expect(reads.requests[3].cursor, 'cursor-2');
    expect(reads.requests[3].libraryViewToken, reads.revisionFencedToken);
    expect(reads.requests[4].cursor, isNull);
    expect(reads.requests[4].libraryViewToken, isNull);
    expect(controller.state.games, [newest]);
    expect(controller.state.lastFailure, isNull);
    final latestPage = controller.pageBoundaryForRow(0)!;
    expect(latestPage.pageOrdinal, 1);
    expect(latestPage.pageStatus, LibraryPageStatus.complete);
    expect(latestPage.observationId, isNot(originalObservation));
    expect(latestPage.observationId, isNot(recoveredObservation));
    expect(continuationRequests, 2);
    controller.dispose();
  });

  test(
    'repeated StaleView after a continuation retry preserves accepted rows',
    () async {
      final first = libraryRow(id: '11111111111111111111111111111111');
      final continuationFailure = libraryApplicationFailure(
        'ARGUS.V1.LIBRARY.STALE_VIEW',
      );
      final retryFailure = libraryApplicationFailure(
        'ARGUS.V1.LIBRARY.STALE_VIEW',
      );
      late final FakeLibraryReads reads;
      reads = FakeLibraryReads()
        ..onListGames = (request) {
          if (request.cursor != null) throw continuationFailure;
          if (reads.requests.length == 1) {
            return GamePage(items: [first], nextCursor: 'cursor-1');
          }
          throw retryFailure;
        };
      final controller = _controller(reads: reads);
      final failed = Completer<void>();
      controller.addListener(() {
        if (identical(controller.state.lastFailure, retryFailure) &&
            !failed.isCompleted) {
          failed.complete();
        }
      });

      await controller.initialize();
      final acceptedObservation = controller
          .rowCorrelationForIndex(0)!
          .observationId;
      final acceptedRowIdentifier = controller
          .rowCorrelationForIndex(0)!
          .semanticsIdentifier;
      await controller.loadMore();
      await failed.future;

      expect(reads.requests, hasLength(3));
      expect(reads.requests[2].cursor, isNull);
      expect(reads.requests[2].libraryViewToken, isNull);
      expect(controller.state.games, [first]);
      expect(controller.state.lastFailure, same(retryFailure));
      expect(controller.state.nextCursor, isNull);
      expect(controller.state.hasMore, isFalse);
      expect(
        controller.rowCorrelationForIndex(0)!.semanticsIdentifier,
        acceptedRowIdentifier,
      );
      final boundaries = controller.trailingPageBoundaries;
      expect(boundaries, hasLength(2));
      expect(
        boundaries.map((page) => page.pageStatus),
        everyElement(LibraryPageStatus.failed),
      );
      expect(boundaries.first.observationId, acceptedObservation);
      expect(boundaries.first.pageOrdinal, 2);
      expect(boundaries.last.observationId, isNot(acceptedObservation));
      expect(boundaries.last.pageOrdinal, 1);

      await controller.loadMore();
      expect(reads.requests, hasLength(3));
      expect(controller.trailingPageBoundaries, boundaries);
      controller.dispose();
    },
  );

  test(
    'InvalidViewToken fails continuation without retry or row mixing',
    () async {
      await _expectFailedContinuationRequiresFreshQuery(
        failure: libraryApplicationFailure(
          'ARGUS.V1.LIBRARY.INVALID_VIEW_TOKEN',
        ),
      );
    },
  );

  test(
    'unknown application failure closes continuation until explicit refresh',
    () async {
      await _expectFailedContinuationRequiresFreshQuery(
        failure: libraryApplicationFailure('ARGUS.V1.LIBRARY.READ_FAILED'),
      );
    },
  );

  test('TransportFailure closes continuation until explicit refresh', () async {
    await _expectFailedContinuationRequiresFreshQuery(
      failure: const TransportFailure(
        'Continuation transport failed',
        kind: TransportFailureKind.communicationFailed,
      ),
    );
  });

  test(
    'unexpected continuation errors close continuation until explicit refresh',
    () async {
      await _expectFailedContinuationRequiresFreshQuery(
        failure: StateError('unexpected continuation error'),
      );
    },
  );

  test('rejects a first page that omits its revision-fenced token', () async {
    final reads = FakeLibraryReads()
      ..omitRevisionFencedToken = true
      ..onListGames = (_) => GamePage(items: [libraryRow()]);
    final controller = _controller(reads: reads);

    await controller.initialize();

    expect(controller.state.games, isEmpty);
    expect(controller.state.lastFailure, isA<TransportFailure>());
    expect(
      (controller.state.lastFailure! as TransportFailure).kind,
      TransportFailureKind.contractMismatch,
    );
    expect(
      controller.emptyStatePageBoundaries.single.pageStatus,
      LibraryPageStatus.failed,
    );
    expect(controller.emptyStatePageBoundaries.single.expectedRowCount, 1);
    controller.dispose();
  });

  test('rejects malformed continuation pages without appending them', () async {
    final first = libraryRow(id: '11111111111111111111111111111111');
    final duplicate = first;
    final second = libraryRow(id: '22222222222222222222222222222222');
    final malformedPages = <GamePage>[
      GamePage(items: [second], libraryViewToken: 'wrong-token'),
      GamePage(items: [second], nextCursor: 'cursor-1'),
      GamePage(items: [duplicate]),
      GamePage(
        items: List<GameLibraryRow>.generate(
          LibraryController.pageSize + 1,
          (index) => libraryRow(id: index.toRadixString(16).padLeft(32, '0')),
        ),
      ),
      const GamePage(items: [], nextCursor: 'cursor-2'),
    ];

    for (final malformedPage in malformedPages) {
      final second = libraryRow(id: '22222222222222222222222222222222');
      final refreshed = libraryRow(id: '33333333333333333333333333333333');
      var continuationRequests = 0;
      late final FakeLibraryReads reads;
      reads = FakeLibraryReads()
        ..onListGames = (request) {
          if (request.cursor == null) {
            return reads.requests.length == 1
                ? GamePage(items: [first], nextCursor: 'cursor-1')
                : GamePage(items: [refreshed]);
          }
          continuationRequests++;
          return continuationRequests == 1
              ? malformedPage
              : GamePage(items: [second]);
        };
      final controller = _controller(reads: reads);

      await controller.initialize();
      final acceptedPage = controller.pageBoundaryForRow(0)!;
      final acceptedRow = controller.rowCorrelationForIndex(0)!;
      await controller.loadMore();

      expect(controller.state.games, [first]);
      expect(controller.state.lastFailure, isA<TransportFailure>());
      expect(
        (controller.state.lastFailure! as TransportFailure).kind,
        TransportFailureKind.contractMismatch,
      );
      expect(
        controller.trailingPageBoundaries.single.pageStatus,
        LibraryPageStatus.failed,
      );
      final failedPage = controller.trailingPageBoundaries.single;
      final failedPageIdentifier = failedPage.semanticsIdentifier;
      final malformedFailure = controller.state.lastFailure;
      expect(failedPage.observationId, acceptedPage.observationId);
      expect(failedPage.pageOrdinal, 2);
      expect(controller.state.nextCursor, isNull);
      expect(controller.state.hasMore, isFalse);
      expect(
        controller.pageBoundaryForRow(0)!.semanticsIdentifier,
        acceptedPage.semanticsIdentifier,
      );
      expect(
        controller.rowCorrelationForIndex(0)!.semanticsIdentifier,
        acceptedRow.semanticsIdentifier,
      );

      for (var attempt = 0; attempt < 3; attempt++) {
        await controller.loadMore();
      }
      expect(reads.requests, hasLength(2));
      expect(
        controller.trailingPageBoundaries.single.semanticsIdentifier,
        failedPageIdentifier,
      );
      expect(controller.state.games, [first]);
      expect(controller.state.lastFailure, same(malformedFailure));

      await controller.refresh();
      expect(reads.requests, hasLength(3));
      expect(reads.requests.last.cursor, isNull);
      expect(reads.requests.last.libraryViewToken, isNull);
      expect(
        reads.requests.last.viewConsistency,
        LibraryViewConsistency.revisionFenced,
      );
      expect(controller.state.games, [refreshed]);
      final refreshedPage = controller.pageBoundaryForRow(0)!;
      expect(refreshedPage.pageOrdinal, 1);
      expect(refreshedPage.pageStatus, LibraryPageStatus.complete);
      expect(refreshedPage.observationId, isNot(acceptedPage.observationId));
      expect(controller.trailingPageBoundaries, isEmpty);
      controller.dispose();
    }
  });

  test('correlates empty first and terminal continuation pages', () async {
    final emptyReads = FakeLibraryReads()
      ..onListGames = (_) => const GamePage(items: []);
    final emptyController = _controller(reads: emptyReads);
    await emptyController.initialize();
    final emptyFirst = emptyController.emptyStatePageBoundaries.single;
    expect(emptyFirst.pageStatus, LibraryPageStatus.complete);
    expect(emptyFirst.expectedRowCount, 0);
    expect(emptyFirst.hasNextPage, isFalse);
    expect(emptyFirst.isFinalPage, isTrue);
    emptyController.dispose();

    final first = libraryRow(id: '11111111111111111111111111111111');
    final continuationReads = FakeLibraryReads()
      ..onListGames = (request) => request.cursor == null
          ? GamePage(items: [first], nextCursor: 'cursor-1')
          : const GamePage(items: []);
    final continuationController = _controller(reads: continuationReads);
    await continuationController.initialize();
    await continuationController.loadMore();

    expect(continuationController.state.games, [first]);
    expect(continuationController.rowCorrelationForIndex(1), isNull);
    final emptyContinuation =
        continuationController.trailingPageBoundaries.single;
    expect(emptyContinuation.pageOrdinal, 2);
    expect(emptyContinuation.pageStatus, LibraryPageStatus.complete);
    expect(emptyContinuation.expectedRowCount, 0);
    expect(emptyContinuation.hasNextPage, isFalse);
    expect(emptyContinuation.isFinalPage, isTrue);
    expect(
      emptyContinuation.observationId,
      continuationController.rowCorrelationForIndex(0)!.observationId,
    );
    continuationController.dispose();
  });

  test(
    'publishes row and page correlation as one controller snapshot',
    () async {
      final first = libraryRow(id: '11111111111111111111111111111111');
      final second = libraryRow(id: '22222222222222222222222222222222');
      final nextPage = Completer<GamePage>();
      final reads = FakeLibraryReads()
        ..onListGames = (request) => request.cursor == null
            ? GamePage(items: [first], nextCursor: 'cursor-1')
            : nextPage.future;
      final controller = _controller(reads: reads);
      final coherentSnapshots = <bool>[];
      controller.addListener(() {
        coherentSnapshots.add(
          List<bool>.generate(controller.state.games.length, (index) {
            final correlation = controller.rowCorrelationForIndex(index);
            return correlation != null &&
                correlation.gameId == controller.state.games[index].gameId;
          }).every((isCoherent) => isCoherent),
        );
      });

      await controller.initialize();
      final observation = controller.rowCorrelationForIndex(0)!.observationId;
      final load = controller.loadMore();
      expect(
        controller.trailingPageBoundaries.single.pageStatus,
        LibraryPageStatus.loading,
      );
      controller.setViewMode(LibraryViewMode.list);
      expect(controller.rowCorrelationForIndex(0)!.observationId, observation);
      expect(reads.requests, hasLength(2));

      nextPage.complete(GamePage(items: [second]));
      await load;

      expect(controller.state.games, [first, second]);
      expect(coherentSnapshots, isNotEmpty);
      expect(coherentSnapshots, everyElement(isTrue));
      expect(controller.rowCorrelationForIndex(1)!.observationId, observation);
      controller.dispose();
    },
  );

  test('late continuation cannot publish across query replacement', () async {
    final first = libraryRow(id: '11111111111111111111111111111111');
    final staleContinuation = Completer<GamePage>();
    final replacementPage = Completer<GamePage>();
    final reads = FakeLibraryReads()
      ..onListGames = (request) {
        if (request.cursor != null) return staleContinuation.future;
        if (request.filters.regions.contains('us')) {
          return replacementPage.future;
        }
        return GamePage(items: [first], nextCursor: 'cursor-1');
      };
    final controller = _controller(reads: reads);
    await controller.initialize();
    final oldObservation = controller.rowCorrelationForIndex(0)!.observationId;

    final oldLoad = controller.loadMore();
    await controller.setFilters(const LibraryFilter(regions: ['us']));
    final newObservation =
        controller.emptyStatePageBoundaries.single.observationId;
    expect(newObservation, isNot(oldObservation));
    staleContinuation.complete(
      GamePage(items: [libraryRow(id: '22222222222222222222222222222222')]),
    );
    await oldLoad;

    expect(controller.state.games, isEmpty);
    expect(reads.requests, hasLength(3));
    expect(
      controller.emptyStatePageBoundaries.single.observationId,
      newObservation,
    );
    expect(
      controller.emptyStatePageBoundaries.single.pageStatus,
      LibraryPageStatus.loading,
    );

    final replacementReady = Completer<void>();
    controller.addListener(() {
      if (controller.state.phase == LibraryLoadPhase.ready &&
          controller.state.filters.regions.contains('us') &&
          !replacementReady.isCompleted) {
        replacementReady.complete();
      }
    });
    final replacement = libraryRow(id: '33333333333333333333333333333333');
    replacementPage.complete(GamePage(items: [replacement]));
    await replacementReady.future;

    expect(controller.state.games, [replacement]);
    expect(controller.rowCorrelationForIndex(0)!.gameId, replacement.gameId);
    expect(controller.rowCorrelationForIndex(0)!.observationId, newObservation);
    controller.dispose();
  });

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
    'cancels a pending search debounce before filter and sort reloads',
    () async {
      final reads = FakeLibraryReads();
      reads.onListGames = (_) => const GamePage(items: []);
      final controller = _controller(
        reads: reads,
        searchDebounce: const Duration(milliseconds: 25),
      );

      await controller.initialize();
      controller.setSearchText('pending-filter');
      await controller.setFilters(const LibraryFilter(regions: ['us']));
      await Future<void>.delayed(const Duration(milliseconds: 75));
      expect(reads.requests, hasLength(2));

      controller.setSearchText('pending-sort');
      await controller.setSort(
        const LibrarySort(
          field: LibrarySortField.updatedAt,
          direction: LibrarySortDirection.descending,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 75));
      expect(reads.requests, hasLength(3));
      controller.dispose();
    },
  );

  test(
    'equivalent runtime contexts retain the route-scoped controller',
    () async {
      final runtimeState =
          NotifierProvider<LibraryRuntimeContextHolder, LibraryRuntimeContext>(
            LibraryRuntimeContextHolder.new,
          );
      final reads = FakeLibraryReads()
        ..onListGames = (_) => const GamePage(items: []);
      final container = ProviderContainer(
        overrides: [
          libraryRuntimeContextProvider.overrideWith(
            (ref) => ref.watch(runtimeState),
          ),
          libraryApiProvider.overrideWithValue(reads),
          librarySourcesApiProvider.overrideWithValue(FakeSourcesApi()),
          libraryRefreshApiProvider.overrideWithValue(FakeLibraryRefreshApi()),
          libraryGamesApiProvider.overrideWithValue(FakeGamesApi()),
          libraryReconciliationDemandProvider.overrideWithValue(
            const LibraryReconciliationDemandSource(
              Stream<LibraryReconciliationDemand>.empty(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      const scope = LibraryScope.platform('nintendo.nes');
      final first = container.read(libraryControllerProvider(scope));
      final controllerSubscription = container.listen(
        libraryControllerProvider(scope),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(controllerSubscription.close);
      await Future<void>.delayed(Duration.zero);
      first.setSearchText('retain this query');

      container
          .read(runtimeState.notifier)
          .replace(
            const LibraryRuntimeContext.ready(
              runtimeInstanceId: RuntimeInstanceId(
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              ),
            ),
          );
      const equivalent = LibraryRuntimeContext.ready(
        runtimeInstanceId: RuntimeInstanceId(
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      );
      expect(container.read(runtimeState), equivalent);
      await Future<void>.delayed(Duration.zero);

      final second = container.read(libraryControllerProvider(scope));
      expect(identical(second, first), isTrue);
      expect(second.state.searchText, 'retain this query');
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

Future<void> _expectFailedContinuationRequiresFreshQuery({
  required Object failure,
}) async {
  final first = libraryRow(id: '11111111111111111111111111111111');
  final retryOnly = libraryRow(id: '22222222222222222222222222222222');
  final refreshed = libraryRow(id: '33333333333333333333333333333333');
  var continuationRequests = 0;
  late final FakeLibraryReads reads;
  reads = FakeLibraryReads()
    ..onListGames = (request) {
      if (request.cursor == null) {
        return reads.requests.length == 1
            ? GamePage(items: [first], nextCursor: 'cursor-1')
            : GamePage(items: [refreshed]);
      }
      continuationRequests++;
      if (continuationRequests == 1) throw failure;
      return GamePage(items: [retryOnly]);
    };
  final controller = _controller(reads: reads);

  try {
    await controller.initialize();
    final acceptedPage = controller.pageBoundaryForRow(0)!;
    final acceptedRow = controller.rowCorrelationForIndex(0)!;
    await controller.loadMore();

    expect(reads.requests, hasLength(2));
    expect(reads.requests.last.cursor, 'cursor-1');
    expect(reads.requests.last.libraryViewToken, reads.revisionFencedToken);
    expect(controller.state.games, [first]);
    expect(controller.state.nextCursor, isNull);
    expect(controller.state.hasMore, isFalse);
    expect(controller.state.loadingMore, isFalse);
    if (failure is ClientFailure) {
      expect(controller.state.lastFailure, same(failure));
    } else {
      final recordedFailure = controller.state.lastFailure;
      expect(recordedFailure, isA<TransportFailure>());
      expect(
        (recordedFailure! as TransportFailure).kind,
        TransportFailureKind.unexpectedTransportFailure,
      );
      expect(recordedFailure.cause, same(failure));
    }

    final recordedFailure = controller.state.lastFailure;
    final failedPage = controller.trailingPageBoundaries.single;
    final failedPageIdentifier = failedPage.semanticsIdentifier;
    expect(failedPage.observationId, acceptedPage.observationId);
    expect(failedPage.pageOrdinal, 2);
    expect(failedPage.pageStatus, LibraryPageStatus.failed);
    expect(failedPage.expectedRowCount, isNull);
    expect(
      controller.pageBoundaryForRow(0)!.semanticsIdentifier,
      acceptedPage.semanticsIdentifier,
    );
    expect(
      controller.rowCorrelationForIndex(0)!.semanticsIdentifier,
      acceptedRow.semanticsIdentifier,
    );

    for (var attempt = 0; attempt < 3; attempt++) {
      await controller.loadMore();
    }
    expect(reads.requests, hasLength(2));
    expect(controller.state.lastFailure, same(recordedFailure));
    expect(controller.state.games, [first]);
    expect(
      controller.trailingPageBoundaries.single.semanticsIdentifier,
      failedPageIdentifier,
    );

    await controller.refresh();
    expect(reads.requests, hasLength(3));
    expect(reads.requests.last.cursor, isNull);
    expect(reads.requests.last.libraryViewToken, isNull);
    expect(
      reads.requests.last.viewConsistency,
      LibraryViewConsistency.revisionFenced,
    );
    expect(controller.state.games, [refreshed]);
    expect(controller.state.lastFailure, isNull);
    expect(controller.trailingPageBoundaries, isEmpty);
    final refreshedPage = controller.pageBoundaryForRow(0)!;
    expect(refreshedPage.pageOrdinal, 1);
    expect(refreshedPage.pageStatus, LibraryPageStatus.complete);
    expect(refreshedPage.observationId, isNot(acceptedPage.observationId));
  } finally {
    controller.dispose();
  }
}

final class LibraryRuntimeContextHolder
    extends Notifier<LibraryRuntimeContext> {
  @override
  LibraryRuntimeContext build() => readyLibraryRuntimeContext;

  void replace(LibraryRuntimeContext value) {
    state = value;
  }
}

LibraryController _controller({
  FakeLibraryReads? reads,
  FakeLibraryRefreshApi? refreshApi,
  FakeGamesApi? gamesApi,
  LibraryScope scope = const LibraryScope.platform('nintendo.nes'),
  Duration? searchDebounce,
}) {
  final libraryReads = reads ?? FakeLibraryReads();
  libraryReads.onListGames ??= (_) => const GamePage(items: []);
  return LibraryController(
    reads: libraryReads,
    sources: FakeSourcesApi(),
    refreshApi: refreshApi ?? FakeLibraryRefreshApi(),
    gamesApi: gamesApi ?? FakeGamesApi(),
    scope: scope,
    runtimeContext: readyLibraryRuntimeContext,
    demandSource: const LibraryReconciliationDemandSource(
      Stream<LibraryReconciliationDemand>.empty(),
    ),
    searchDebounce: searchDebounce ?? LibraryController.defaultSearchDebounce,
  );
}
