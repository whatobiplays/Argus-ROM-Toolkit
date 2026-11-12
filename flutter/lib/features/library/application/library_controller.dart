// The constructor keeps public parameter names while assigning private fields.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library_composition.dart';
import 'library_state.dart';

/// Status of a page attempt in a single Library observation.
enum LibraryPageStatus { loading, complete, failed }

/// Metadata exposed through Flutter semantics for one requested page.
///
/// The identifier carries the observation and page facts an independent
/// hierarchy reader needs. It never includes the backend token or cursor.
final class LibraryPageCorrelation {
  const LibraryPageCorrelation({
    required this.observationId,
    required this.queryProfile,
    required this.pageOrdinal,
    required this.isFirstPage,
    required this.isContinuationPage,
    required this.pageStatus,
    required this.hasNextPage,
    required this.isFinalPage,
    required this.pageSize,
    required this.expectedRowCount,
  });

  final String observationId;
  final String queryProfile;
  final int pageOrdinal;
  final bool isFirstPage;
  final bool isContinuationPage;
  final LibraryPageStatus pageStatus;
  final bool? hasNextPage;
  final bool? isFinalPage;
  final int pageSize;
  final int? expectedRowCount;

  /// Stable, nonspoken encoding for one independently queryable page node.
  String get semanticsIdentifier => [
    'argus.library.page.v1',
    'observation=${Uri.encodeComponent(observationId)}',
    'profile=$queryProfile',
    'page=$pageOrdinal',
    'first=$isFirstPage',
    'continuation=$isContinuationPage',
    'status=${pageStatus.name}',
    'hasNext=${hasNextPage?.toString() ?? 'unknown'}',
    'final=${isFinalPage?.toString() ?? 'unknown'}',
    'pageSize=$pageSize',
    'expectedRows=${expectedRowCount?.toString() ?? 'unknown'}',
  ].join(';');
}

/// Correlates one rendered Library row with its page and exact GameId.
final class LibraryRowCorrelation {
  const LibraryRowCorrelation({
    required this.observationId,
    required this.pageOrdinal,
    required this.rowOrdinalWithinPage,
    required this.gameId,
  });

  final String observationId;
  final int pageOrdinal;
  final int rowOrdinalWithinPage;
  final GameId gameId;

  /// Stable, nonspoken encoding for the row's independently queryable node.
  String get semanticsIdentifier => [
    'argus.library.row.v1',
    'observation=${Uri.encodeComponent(observationId)}',
    'page=$pageOrdinal',
    'row=$rowOrdinalWithinPage',
    'gameId=${Uri.encodeComponent(gameId.value)}',
  ].join(';');
}

final class _LibraryQueryShape {
  const _LibraryQueryShape({
    required this.scope,
    required this.searchText,
    required this.filters,
    required this.sort,
    required this.pageSize,
  });

  factory _LibraryQueryShape.fromState(LibraryState state) =>
      _LibraryQueryShape(
        scope: state.scope,
        searchText: state.searchText,
        filters: state.filters,
        sort: state.sort,
        pageSize: LibraryController.pageSize,
      );

  final LibraryScope scope;
  final String? searchText;
  final LibraryFilter filters;
  final LibrarySort sort;
  final int pageSize;

  ListGamesRequest request({String? cursor, String? viewToken}) =>
      ListGamesRequest(
        scope: scope,
        searchText: searchText,
        filters: filters,
        sort: sort,
        cursor: cursor,
        pageSize: pageSize,
        viewConsistency: LibraryViewConsistency.revisionFenced,
        libraryViewToken: viewToken,
      );
}

final class _LibraryAcceptedPage {
  const _LibraryAcceptedPage({
    required this.correlation,
    required this.firstRowIndex,
    required this.rowCount,
  });

  final LibraryPageCorrelation correlation;
  final int firstRowIndex;
  final int rowCount;
}

/// Immutable controller data for one request chain. Tokens and cursors remain
/// here and are never copied into LibraryState or semantics identifiers.
final class _LibraryObservation {
  _LibraryObservation({
    required this.observationId,
    required this.queryShape,
    required this.queryProfile,
    this.viewToken,
    this.nextCursor,
    this.canContinue = true,
    List<_LibraryAcceptedPage> pages = const [],
    Set<GameId> seenGameIds = const {},
    Set<String> requestedCursors = const {},
  }) : pages = List.unmodifiable(pages),
       seenGameIds = Set.unmodifiable(seenGameIds),
       requestedCursors = Set.unmodifiable(requestedCursors);

  final String observationId;
  final _LibraryQueryShape queryShape;
  final String queryProfile;
  final String? viewToken;
  final String? nextCursor;
  final bool canContinue;
  final List<_LibraryAcceptedPage> pages;
  final Set<GameId> seenGameIds;
  final Set<String> requestedCursors;

  _LibraryObservation acceptPage(GamePage page, String? requestCursor) {
    final pageOrdinal = pages.length + 1;
    final firstRowIndex = pages.isEmpty
        ? 0
        : pages.last.firstRowIndex + pages.last.rowCount;
    final correlation = LibraryPageCorrelation(
      observationId: observationId,
      queryProfile: queryProfile,
      pageOrdinal: pageOrdinal,
      isFirstPage: pageOrdinal == 1,
      isContinuationPage: pageOrdinal > 1,
      pageStatus: LibraryPageStatus.complete,
      hasNextPage: page.nextCursor != null,
      isFinalPage: page.nextCursor == null,
      pageSize: queryShape.pageSize,
      expectedRowCount: page.items.length,
    );
    final updatedCursors = {...requestedCursors};
    if (requestCursor != null) updatedCursors.add(requestCursor);
    return _LibraryObservation(
      observationId: observationId,
      queryShape: queryShape,
      queryProfile: queryProfile,
      viewToken: viewToken ?? page.libraryViewToken,
      nextCursor: page.nextCursor,
      canContinue: page.nextCursor != null,
      pages: [
        ...pages,
        _LibraryAcceptedPage(
          correlation: correlation,
          firstRowIndex: firstRowIndex,
          rowCount: page.items.length,
        ),
      ],
      seenGameIds: {...seenGameIds, ...page.items.map((row) => row.gameId)},
      requestedCursors: updatedCursors,
    );
  }

  _LibraryObservation withoutContinuation() => _LibraryObservation(
    observationId: observationId,
    queryShape: queryShape,
    queryProfile: queryProfile,
    canContinue: false,
    pages: pages,
    seenGameIds: seenGameIds,
    requestedCursors: requestedCursors,
  );
}

/// Owns one route-scoped Library query, its bounded continuation, and
/// presentation-only selection/layout state.
///
/// The controller never filters or sorts rows locally. Every query-shaping
/// change starts a new backend request, and request/runtime tokens prevent a
/// late response from an older query or runtime generation becoming visible.
enum _LibraryRequestStage { page, auxiliary }

final class LibraryController extends ChangeNotifier {
  static const int pageSize = 50;
  static const int maxRefreshSelected = 64;
  static const Duration defaultSearchDebounce = Duration(milliseconds: 300);
  static const String ordinaryUserQueryProfile = 'OrdinaryUserQuery';
  static const String allActiveMembershipBaselineProfile =
      'AllActiveMembershipBaseline';
  static int _observationSequence = 0;
  static int _pageStorageInstanceSequence = 0;

  /// Stable primitive identity used to isolate this controller's saved offsets.
  final int pageStorageInstanceId = ++_pageStorageInstanceSequence;

  LibraryController({
    required LibraryReads reads,
    required SourcesApi sources,
    required LibraryRefreshApi refreshApi,
    required GamesApi gamesApi,
    required LibraryScope scope,
    required LibraryRuntimeContext runtimeContext,
    required LibraryReconciliationDemandSource demandSource,
    Duration searchDebounce = defaultSearchDebounce,
  }) : _reads = reads,
       _sources = sources,
       _refreshApi = refreshApi,
       _gamesApi = gamesApi,
       _runtimeContext = runtimeContext,
       _searchDebounce = searchDebounce,
       _state = LibraryState.initial(scope) {
    _subscribeToDemands(demandSource);
  }

  /// Creates a controller that can render the pre-ready state without
  /// resolving capabilities owned by the ready runtime generation.
  ///
  /// The route provider switches to the fully composed constructor when the
  /// runtime context becomes ready. Keeping this state dependency-free avoids
  /// turning the shell's pre-ready surface into a capability-resolution error.
  LibraryController.preReady({
    required LibraryScope scope,
    required LibraryRuntimeContext runtimeContext,
    required LibraryReconciliationDemandSource demandSource,
    Duration searchDebounce = defaultSearchDebounce,
  }) : _reads = null,
       _sources = null,
       _refreshApi = null,
       _gamesApi = null,
       _runtimeContext = runtimeContext,
       _searchDebounce = searchDebounce,
       _state = LibraryState.initial(scope) {
    _subscribeToDemands(demandSource);
  }

  final LibraryReads? _reads;
  final SourcesApi? _sources;
  final LibraryRefreshApi? _refreshApi;
  final GamesApi? _gamesApi;
  final LibraryRuntimeContext _runtimeContext;
  final Duration _searchDebounce;

  LibraryState _state;
  _LibraryObservation? _rowsObservation;
  _LibraryObservation? _requestObservation;
  LibraryPageCorrelation? _pendingPageCorrelation;
  List<LibraryPageCorrelation> _retainedStaleFailureBoundaries =
      const <LibraryPageCorrelation>[];
  StreamSubscription<LibraryReconciliationDemand>? _demandSubscription;
  Timer? _searchTimer;
  int _requestToken = 0;
  bool _requestInFlight = false;
  bool _reloadAfterRequest = false;
  bool _initialized = false;
  bool _disposed = false;
  bool _staleRecoveryUsed = false;
  GameId? _selectionAnchor;
  int _scrollResetGeneration = 0;

  LibraryState get state => _state;

  /// Whether the normal Library page can select the all-active query.
  bool get canResetAllActive => _isReady && _state.scope is LibraryScopeAll;

  /// Starts a fresh All-scope observation after a deliberate user action.
  ///
  /// The baseline profile belongs to this in-memory observation and follows
  /// its pages through continuation and stale-view recovery.
  Future<void> resetAllActive() {
    if (!canResetAllActive) return Future<void>.value();

    _searchTimer?.cancel();
    _requestToken++;
    _staleRecoveryUsed = false;
    _retainedStaleFailureBoundaries = const <LibraryPageCorrelation>[];
    _selectionAnchor = null;
    _scrollResetGeneration++;

    final nextState = _state.copyWith(
      searchText: null,
      filters: const LibraryFilter(),
      sort: const LibrarySort(),
      games: const <GameLibraryRow>[],
      nextCursor: null,
      facets: null,
      roots: null,
      phase: LibraryLoadPhase.loading,
      refreshing: false,
      loadingMore: false,
      lastFailure: null,
      selectedGameIds: const <GameId>{},
      gridScrollOffset: 0,
      listScrollOffset: 0,
    );
    final observation = _newObservation(
      nextState,
      queryProfile: allActiveMembershipBaselineProfile,
    );
    _publish(
      state: nextState,
      rowsObservation: null,
      requestObservation: observation,
      pendingPageCorrelation: _pageAttempt(
        observation,
        pageOrdinal: 1,
        status: LibraryPageStatus.loading,
      ),
    );
    return _load();
  }

  /// Changes when both saved layout offsets must be discarded.
  int get scrollResetGeneration => _scrollResetGeneration;

  /// Returns the page boundary attached to the first row of a completed page.
  LibraryPageCorrelation? pageBoundaryForRow(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= _state.games.length) return null;
    for (final page
        in _rowsObservation?.pages ?? const <_LibraryAcceptedPage>[]) {
      if (page.rowCount > 0 && page.firstRowIndex == rowIndex) {
        return page.correlation;
      }
    }
    return null;
  }

  /// Returns the accepted page and one-based row identity at [rowIndex].
  LibraryRowCorrelation? rowCorrelationForIndex(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= _state.games.length) return null;
    for (final page
        in _rowsObservation?.pages ?? const <_LibraryAcceptedPage>[]) {
      final rowOffset = rowIndex - page.firstRowIndex;
      if (page.rowCount > 0 && rowOffset >= 0 && rowOffset < page.rowCount) {
        return LibraryRowCorrelation(
          observationId: page.correlation.observationId,
          pageOrdinal: page.correlation.pageOrdinal,
          rowOrdinalWithinPage: rowOffset + 1,
          gameId: _state.games[rowIndex].gameId,
        );
      }
    }
    return null;
  }

  /// Boundaries shown with empty-state content, including an older accepted
  /// empty result retained while a fresh first page is loading or failing.
  List<LibraryPageCorrelation> get emptyStatePageBoundaries {
    if (_state.games.isNotEmpty) return const [];
    final boundaries = <LibraryPageCorrelation>[
      for (final page
          in _rowsObservation?.pages ?? const <_LibraryAcceptedPage>[])
        if (page.rowCount == 0) page.correlation,
      ..._retainedStaleFailureBoundaries,
    ];
    final pending = _pendingPageCorrelation;
    if (pending != null) boundaries.add(pending);
    return List.unmodifiable(boundaries);
  }

  /// Boundaries for empty or in-progress pages after the currently retained
  /// rows. Each entry becomes its own semantics node in the scrollable footer.
  List<LibraryPageCorrelation> get trailingPageBoundaries {
    if (_state.games.isEmpty) return const [];
    final boundaries = <LibraryPageCorrelation>[
      for (final page
          in _rowsObservation?.pages ?? const <_LibraryAcceptedPage>[])
        if (page.rowCount == 0) page.correlation,
      ..._retainedStaleFailureBoundaries,
    ];
    final pending = _pendingPageCorrelation;
    if (pending != null) boundaries.add(pending);
    return List.unmodifiable(boundaries);
  }

  /// Starts the first authoritative read once the runtime generation is ready.
  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    _initialized = true;
    if (_runtimeContext is LibraryRuntimeContextPreReady) {
      return Future<void>.value();
    }
    return _load();
  }

  /// Re-reads the current scope/search/filter/sort shape from the backend.
  Future<void> refresh() {
    _searchTimer?.cancel();
    _requestToken++;
    final profile =
        (_requestObservation ?? _rowsObservation)?.queryProfile ??
        ordinaryUserQueryProfile;
    _requestObservation = _newObservation(_state, queryProfile: profile);
    _staleRecoveryUsed = false;
    _retainedStaleFailureBoundaries = const <LibraryPageCorrelation>[];
    return _load();
  }

  /// Loads one bounded continuation page, if the backend supplied a cursor.
  Future<void> loadMore() => _load(loadMore: true);

  /// Updates backend-owned search text and applies it after the debounce.
  void setSearchText(String? searchText) {
    _searchTimer?.cancel();
    _requestToken++;
    _staleRecoveryUsed = false;
    _retainedStaleFailureBoundaries = const <LibraryPageCorrelation>[];
    final nextState = _state.copyWith(
      searchText: searchText,
      games: const <GameLibraryRow>[],
      nextCursor: null,
      facets: null,
      phase: _isReady ? LibraryLoadPhase.loading : LibraryLoadPhase.preReady,
      refreshing: false,
      loadingMore: false,
      lastFailure: null,
    );
    final observation = _newObservation(nextState);
    _publish(
      state: nextState,
      rowsObservation: null,
      requestObservation: observation,
      pendingPageCorrelation: _pageAttempt(
        observation,
        pageOrdinal: 1,
        status: LibraryPageStatus.loading,
      ),
    );
    _searchTimer = Timer(_searchDebounce, () => unawaited(_load()));
  }

  /// Replaces the complete backend-owned filter shape and reloads it.
  Future<void> setFilters(LibraryFilter filters) {
    _searchTimer?.cancel();
    _requestToken++;
    _staleRecoveryUsed = false;
    _retainedStaleFailureBoundaries = const <LibraryPageCorrelation>[];
    final nextState = _state.copyWith(
      filters: filters,
      games: const <GameLibraryRow>[],
      nextCursor: null,
      facets: null,
      phase: _isReady ? LibraryLoadPhase.loading : LibraryLoadPhase.preReady,
      refreshing: false,
      loadingMore: false,
      lastFailure: null,
    );
    final observation = _newObservation(nextState);
    _publish(
      state: nextState,
      rowsObservation: null,
      requestObservation: observation,
      pendingPageCorrelation: _pageAttempt(
        observation,
        pageOrdinal: 1,
        status: LibraryPageStatus.loading,
      ),
    );
    return _load();
  }

  /// Replaces the backend-owned sort shape and reloads it from page one.
  Future<void> setSort(LibrarySort sort) {
    _searchTimer?.cancel();
    _requestToken++;
    _staleRecoveryUsed = false;
    _retainedStaleFailureBoundaries = const <LibraryPageCorrelation>[];
    final nextState = _state.copyWith(
      sort: sort,
      games: const <GameLibraryRow>[],
      nextCursor: null,
      facets: null,
      phase: _isReady ? LibraryLoadPhase.loading : LibraryLoadPhase.preReady,
      refreshing: false,
      loadingMore: false,
      lastFailure: null,
    );
    final observation = _newObservation(nextState);
    _publish(
      state: nextState,
      rowsObservation: null,
      requestObservation: observation,
      pendingPageCorrelation: _pageAttempt(
        observation,
        pageOrdinal: 1,
        status: LibraryPageStatus.loading,
      ),
    );
    return _load();
  }

  /// Changes only the presentation arrangement; rows remain backend-owned.
  void setViewMode(LibraryViewMode viewMode) {
    if (_state.viewMode == viewMode) return;
    _state = _state.copyWith(viewMode: viewMode);
    _notify();
  }

  /// Retains the scroll position for route restoration without querying data.
  void setScrollOffset(double scrollOffset) {
    if (_state.scrollOffset == scrollOffset) return;
    _state = _state.viewMode == LibraryViewMode.grid
        ? _state.copyWith(gridScrollOffset: scrollOffset)
        : _state.copyWith(listScrollOffset: scrollOffset);
    _notify();
  }

  /// Toggles one loaded Game in the presentation-owned selection set.
  void toggleSelection(GameId gameId) {
    final selected = {..._state.selectedGameIds};
    if (!selected.add(gameId)) selected.remove(gameId);
    _selectionAnchor = gameId;
    _state = _state.copyWith(selectedGameIds: Set.unmodifiable(selected));
    _notify();
  }

  /// Adds the loaded row range between the current anchor and [gameId].
  ///
  /// Range selection is deliberately limited to rows already returned by the
  /// backend. It never turns a keyboard gesture into an unbounded Library
  /// fetch, and the selected identities remain stable when row order changes.
  void selectRange(GameId gameId) {
    final anchor = _selectionAnchor;
    final orderedIds = _state.games.map((row) => row.gameId).toList();
    final targetIndex = orderedIds.indexOf(gameId);
    final anchorIndex = anchor == null ? -1 : orderedIds.indexOf(anchor);
    if (anchorIndex < 0 || targetIndex < 0) {
      toggleSelection(gameId);
      return;
    }

    final start = anchorIndex < targetIndex ? anchorIndex : targetIndex;
    final end = anchorIndex < targetIndex ? targetIndex : anchorIndex;
    final selected = {..._state.selectedGameIds}
      ..addAll(orderedIds.sublist(start, end + 1));
    _selectionAnchor = gameId;
    _state = _state.copyWith(selectedGameIds: Set.unmodifiable(selected));
    _notify();
  }

  /// Clears all selected Games without affecting the current query.
  void clearSelection() {
    _selectionAnchor = null;
    if (_state.selectedGameIds.isEmpty) return;
    _state = _state.copyWith(selectedGameIds: const <GameId>{});
    _notify();
  }

  /// Starts the bounded multi-Game refresh contract using EligibleOnly.
  ///
  /// A null result means no operation was submitted because the selection was
  /// empty or exceeded the transport bound. Force is intentionally absent from
  /// this bulk method; it is available only through [forceRefresh].
  Future<OperationHandle?> refreshSelected() async {
    final gameIds = _sortedSelectedIds();
    if (gameIds.isEmpty || gameIds.length > maxRefreshSelected) return null;
    final refreshApi = _refreshApi;
    if (refreshApi == null) return null;
    return refreshApi.startGameRefresh(
      gameIds: gameIds,
      mode: RefreshMode.eligibleOnly,
    );
  }

  /// Starts a single-Game Force refresh. It cannot accept a bulk set.
  Future<OperationHandle> forceRefresh(GameId gameId) {
    final gamesApi = _gamesApi;
    if (gamesApi == null) {
      return Future<OperationHandle>.error(
        const TransportFailure('Library runtime is not ready'),
      );
    }
    return gamesApi.refreshGame(gameId: gameId, mode: RefreshMode.force);
  }

  bool get _isReady => _runtimeContext is LibraryRuntimeContextReady;

  Future<void> _load({bool loadMore = false}) async {
    if (_disposed || !_isReady) return;
    final reads = _reads;
    final sources = _sources;
    if (reads == null || sources == null) return;
    if (_requestInFlight) {
      if (!loadMore) _reloadAfterRequest = true;
      return;
    }
    if (loadMore && (!_state.hasMore || _state.loadingMore)) return;

    final _LibraryObservation observation;
    if (loadMore) {
      final current = _requestObservation;
      if (current == null ||
          !identical(current, _rowsObservation) ||
          !current.canContinue ||
          current.nextCursor == null ||
          current.nextCursor != _state.nextCursor ||
          current.viewToken == null) {
        return;
      }
      observation = current;
    } else {
      var current = _requestObservation;
      if (current == null || identical(current, _rowsObservation)) {
        current = _newObservation(_state);
      }
      observation = current;
    }

    final cursor = loadMore ? observation.nextCursor : null;
    final request = observation.queryShape.request(
      cursor: cursor,
      viewToken: loadMore ? observation.viewToken : null,
    );
    final pageOrdinal = observation.pages.length + 1;
    final pendingPage = _pageAttempt(
      observation,
      pageOrdinal: pageOrdinal,
      status: LibraryPageStatus.loading,
    );
    final hadRows = _state.games.isNotEmpty;
    final loadingState = loadMore
        ? _state.copyWith(loadingMore: true, lastFailure: null)
        : _state.copyWith(
            phase: LibraryLoadPhase.loading,
            nextCursor: null,
            refreshing: hadRows,
            loadingMore: false,
            lastFailure: _retainedStaleFailureBoundaries.isEmpty
                ? null
                : _state.lastFailure,
          );

    _requestInFlight = true;
    final token = ++_requestToken;
    _publish(
      state: loadingState,
      rowsObservation: _rowsObservation,
      requestObservation: observation,
      pendingPageCorrelation: pendingPage,
    );

    var requestStage = _LibraryRequestStage.page;
    GamePage? response;
    try {
      final page = await reads.listGames(request);
      response = page;
      if (!_canPublish(token)) return;
      final contractFailure = _pageResponseFailure(
        observation: observation,
        response: page,
        cursor: cursor,
        isContinuation: loadMore,
      );
      if (contractFailure != null) {
        _publishLoadFailure(
          observation: observation,
          failure: contractFailure,
          response: page,
          closeContinuation: true,
        );
        return;
      }

      requestStage = _LibraryRequestStage.auxiliary;
      LibraryFacets? facets;
      LibraryRootPage? roots;
      if (!loadMore) {
        facets = await reads.getLibraryFacets(
          LibraryFacetQuery(
            scope: observation.queryShape.scope,
            searchText: observation.queryShape.searchText,
            filters: observation.queryShape.filters,
          ),
        );
        if (observation.queryShape.scope is LibraryScopeAll) {
          roots = await sources.listLibraryRoots(offset: 0, pageSize: pageSize);
        }
      }
      if (!_canPublish(token)) return;
      final acceptedObservation = observation.acceptPage(page, cursor);
      if (!loadMore) {
        _staleRecoveryUsed = false;
        _retainedStaleFailureBoundaries = const <LibraryPageCorrelation>[];
      }
      final rows = loadMore ? [..._state.games, ...page.items] : page.items;
      final nextState = _state.copyWith(
        games: List.unmodifiable(rows),
        nextCursor: page.nextCursor,
        facets: loadMore ? _state.facets : facets,
        roots: loadMore ? _state.roots : roots,
        phase: LibraryLoadPhase.ready,
        refreshing: false,
        loadingMore: false,
        lastFailure: null,
      );
      _publish(
        state: nextState,
        rowsObservation: acceptedObservation,
        requestObservation: acceptedObservation,
        pendingPageCorrelation: null,
      );
    } on ApplicationFailure catch (failure) {
      if (!_canPublish(token)) return;
      final code = failure.error.code.value;
      if (requestStage == _LibraryRequestStage.page &&
          code == 'ARGUS.V1.LIBRARY.STALE_VIEW') {
        _handleStaleView(observation, failure);
        return;
      }
      _publishLoadFailure(
        observation: observation,
        failure: failure,
        response: response,
        closeContinuation:
            loadMore ||
            code == 'ARGUS.V1.LIBRARY.INVALID_VIEW_TOKEN' ||
            requestStage == _LibraryRequestStage.auxiliary,
      );
    } on ClientFailure catch (failure) {
      if (!_canPublish(token)) return;
      _publishLoadFailure(
        observation: observation,
        failure: failure,
        response: response,
        closeContinuation:
            loadMore || requestStage == _LibraryRequestStage.auxiliary,
      );
    } catch (error, stackTrace) {
      if (!_canPublish(token)) return;
      _publishLoadFailure(
        observation: observation,
        failure: TransportFailure(
          'The Library query failed',
          kind: TransportFailureKind.unexpectedTransportFailure,
          cause: error,
          stackTrace: stackTrace,
        ),
        response: response,
        closeContinuation:
            loadMore || requestStage == _LibraryRequestStage.auxiliary,
      );
    } finally {
      _requestInFlight = false;
      if (!_disposed && _reloadAfterRequest) {
        _reloadAfterRequest = false;
        unawaited(_load());
      }
    }
  }

  _LibraryObservation _newObservation(
    LibraryState state, {
    String queryProfile = ordinaryUserQueryProfile,
  }) => _LibraryObservation(
    observationId: 'obs-${++_observationSequence}',
    queryShape: _LibraryQueryShape.fromState(state),
    queryProfile: queryProfile,
  );

  LibraryPageCorrelation _pageAttempt(
    _LibraryObservation observation, {
    required int pageOrdinal,
    required LibraryPageStatus status,
    GamePage? response,
  }) => LibraryPageCorrelation(
    observationId: observation.observationId,
    queryProfile: observation.queryProfile,
    pageOrdinal: pageOrdinal,
    isFirstPage: pageOrdinal == 1,
    isContinuationPage: pageOrdinal > 1,
    pageStatus: status,
    hasNextPage: response == null ? null : response.nextCursor != null,
    isFinalPage: response == null ? null : response.nextCursor == null,
    pageSize: observation.queryShape.pageSize,
    expectedRowCount: response?.items.length,
  );

  TransportFailure? _pageResponseFailure({
    required _LibraryObservation observation,
    required GamePage response,
    required String? cursor,
    required bool isContinuation,
  }) {
    final pageIds = <GameId>{};
    final invalidToken =
        response.libraryViewToken == null ||
        response.libraryViewToken!.isEmpty ||
        (isContinuation && response.libraryViewToken != observation.viewToken);
    final repeatedCursor =
        response.nextCursor != null &&
        (response.nextCursor!.isEmpty ||
            response.nextCursor == cursor ||
            observation.requestedCursors.contains(response.nextCursor));
    final duplicateGameId = response.items.any(
      (row) =>
          !pageIds.add(row.gameId) ||
          (isContinuation && observation.seenGameIds.contains(row.gameId)),
    );
    if (invalidToken ||
        response.items.length > observation.queryShape.pageSize ||
        repeatedCursor ||
        (response.items.isEmpty && response.nextCursor != null) ||
        duplicateGameId) {
      return const TransportFailure(
        'The Library page did not match its revision-fenced request',
        kind: TransportFailureKind.contractMismatch,
      );
    }
    return null;
  }

  void _publishLoadFailure({
    required _LibraryObservation observation,
    required ClientFailure failure,
    required GamePage? response,
    required bool closeContinuation,
  }) {
    final pending =
        _pendingPageCorrelation ??
        _pageAttempt(
          observation,
          pageOrdinal: observation.pages.length + 1,
          status: LibraryPageStatus.loading,
        );
    final failedPage = LibraryPageCorrelation(
      observationId: pending.observationId,
      queryProfile: pending.queryProfile,
      pageOrdinal: pending.pageOrdinal,
      isFirstPage: pending.isFirstPage,
      isContinuationPage: pending.isContinuationPage,
      pageStatus: LibraryPageStatus.failed,
      hasNextPage: response == null ? null : response.nextCursor != null,
      isFinalPage: response == null ? null : response.nextCursor == null,
      pageSize: pending.pageSize,
      expectedRowCount: response?.items.length,
    );
    final nextState = _state.copyWith(
      nextCursor: closeContinuation ? null : _state.nextCursor,
      phase: _state.games.isEmpty
          ? LibraryLoadPhase.failed
          : LibraryLoadPhase.ready,
      refreshing: false,
      loadingMore: false,
      lastFailure: failure,
    );
    _publish(
      state: nextState,
      rowsObservation: _rowsObservation,
      requestObservation: closeContinuation
          ? observation.withoutContinuation()
          : observation,
      pendingPageCorrelation: failedPage,
    );
  }

  void _handleStaleView(
    _LibraryObservation observation,
    ApplicationFailure failure,
  ) {
    if (!_staleRecoveryUsed) {
      _staleRecoveryUsed = true;
      final pending =
          _pendingPageCorrelation ??
          _pageAttempt(
            observation,
            pageOrdinal: observation.pages.length + 1,
            status: LibraryPageStatus.loading,
          );
      _retainedStaleFailureBoundaries = [
        ..._retainedStaleFailureBoundaries,
        _failedPageBoundary(pending),
      ];
      final nextState = _state.copyWith(
        nextCursor: null,
        phase: LibraryLoadPhase.loading,
        refreshing: _state.games.isNotEmpty,
        loadingMore: false,
        lastFailure: failure,
      );
      final replacement = _newObservation(
        nextState,
        queryProfile: observation.queryProfile,
      );
      _publish(
        state: nextState,
        rowsObservation: _rowsObservation,
        requestObservation: replacement,
        pendingPageCorrelation: _pageAttempt(
          replacement,
          pageOrdinal: 1,
          status: LibraryPageStatus.loading,
        ),
      );
      _reloadAfterRequest = true;
      return;
    }

    final pending =
        _pendingPageCorrelation ??
        _pageAttempt(
          observation,
          pageOrdinal: observation.pages.length + 1,
          status: LibraryPageStatus.loading,
        );
    final failedPage = _failedPageBoundary(pending);
    final retainRows =
        _retainedStaleFailureBoundaries.isNotEmpty && _state.games.isNotEmpty;
    _publish(
      state: _state.copyWith(
        nextCursor: null,
        phase: retainRows ? LibraryLoadPhase.ready : LibraryLoadPhase.failed,
        refreshing: false,
        loadingMore: false,
        lastFailure: failure,
      ),
      rowsObservation: _rowsObservation,
      requestObservation: observation.withoutContinuation(),
      pendingPageCorrelation: failedPage,
    );
  }

  LibraryPageCorrelation _failedPageBoundary(LibraryPageCorrelation pending) =>
      LibraryPageCorrelation(
        observationId: pending.observationId,
        queryProfile: pending.queryProfile,
        pageOrdinal: pending.pageOrdinal,
        isFirstPage: pending.isFirstPage,
        isContinuationPage: pending.isContinuationPage,
        pageStatus: LibraryPageStatus.failed,
        hasNextPage: null,
        isFinalPage: null,
        pageSize: pending.pageSize,
        expectedRowCount: null,
      );

  /// Installs rows and their immutable page ledger before notifying the page.
  void _publish({
    required LibraryState state,
    required _LibraryObservation? rowsObservation,
    required _LibraryObservation? requestObservation,
    required LibraryPageCorrelation? pendingPageCorrelation,
  }) {
    _rowsObservation = rowsObservation;
    _requestObservation = requestObservation;
    _pendingPageCorrelation = pendingPageCorrelation;
    _state = state;
    _notify();
  }

  void _subscribeToDemands(LibraryReconciliationDemandSource source) {
    _demandSubscription = source.stream.listen((demand) {
      if (_disposed) return;
      switch (demand) {
        case LibraryReconciliationDemandListChanged():
        case LibraryReconciliationDemandDetailChanged():
          unawaited(refresh());
      }
    });
  }

  List<GameId> _sortedSelectedIds() {
    final ids = _state.selectedGameIds.toList();
    ids.sort((left, right) => left.value.compareTo(right.value));
    return List.unmodifiable(ids);
  }

  bool _canPublish(int token) =>
      !_disposed &&
      token == _requestToken &&
      _runtimeContext is LibraryRuntimeContextReady;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _requestToken++;
    _searchTimer?.cancel();
    unawaited(_demandSubscription?.cancel());
    super.dispose();
  }
}

/// Route-scoped controller provider; Riverpod disposes it with the Library
/// branch, while the controller owns only bounded query/presentation state.
final libraryControllerProvider = Provider.autoDispose
    .family<LibraryController, LibraryScope>((ref, scope) {
      final runtimeContext = ref.watch(libraryRuntimeContextProvider);
      final demandSource = ref.watch(libraryReconciliationDemandProvider);
      final controller = switch (runtimeContext) {
        LibraryRuntimeContextPreReady() => LibraryController.preReady(
          scope: scope,
          runtimeContext: runtimeContext,
          demandSource: demandSource,
        ),
        LibraryRuntimeContextReady() => LibraryController(
          reads: ref.watch(libraryApiProvider),
          sources: ref.watch(librarySourcesApiProvider),
          refreshApi: ref.watch(libraryRefreshApiProvider),
          gamesApi: ref.watch(libraryGamesApiProvider),
          scope: scope,
          runtimeContext: runtimeContext,
          demandSource: demandSource,
        ),
      };
      ref.onDispose(controller.dispose);
      unawaited(controller.initialize());
      return controller;
    });
