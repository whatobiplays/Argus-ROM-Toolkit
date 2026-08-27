// The constructor keeps public parameter names while assigning private fields.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library_composition.dart';
import 'library_state.dart';

/// Owns one route-scoped Library query, its bounded continuation, and
/// presentation-only selection/layout state.
///
/// The controller never filters or sorts rows locally. Every query-shaping
/// change starts a new backend request, and request/runtime tokens prevent a
/// late response from an older query or runtime generation becoming visible.
final class LibraryController extends ChangeNotifier {
  static const int pageSize = 50;
  static const int maxRefreshSelected = 64;
  static const Duration defaultSearchDebounce = Duration(milliseconds: 300);

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
       _scope = scope,
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
       _scope = scope,
       _runtimeContext = runtimeContext,
       _searchDebounce = searchDebounce,
       _state = LibraryState.initial(scope) {
    _subscribeToDemands(demandSource);
  }

  final LibraryReads? _reads;
  final SourcesApi? _sources;
  final LibraryRefreshApi? _refreshApi;
  final GamesApi? _gamesApi;
  final LibraryScope _scope;
  final LibraryRuntimeContext _runtimeContext;
  final Duration _searchDebounce;

  LibraryState _state;
  StreamSubscription<LibraryReconciliationDemand>? _demandSubscription;
  Timer? _searchTimer;
  int _requestToken = 0;
  bool _requestInFlight = false;
  bool _reloadAfterRequest = false;
  bool _initialized = false;
  bool _disposed = false;
  GameId? _selectionAnchor;

  LibraryState get state => _state;

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
    return _load();
  }

  /// Loads one bounded continuation page, if the backend supplied a cursor.
  Future<void> loadMore() => _load(loadMore: true);

  /// Updates backend-owned search text and applies it after the debounce.
  void setSearchText(String? searchText) {
    _searchTimer?.cancel();
    _requestToken++;
    _state = _state.copyWith(
      searchText: searchText,
      games: const <GameLibraryRow>[],
      nextCursor: null,
      facets: null,
      phase: _isReady ? LibraryLoadPhase.loading : LibraryLoadPhase.preReady,
      refreshing: false,
      loadingMore: false,
      lastFailure: null,
    );
    _notify();
    _searchTimer = Timer(_searchDebounce, () => unawaited(_load()));
  }

  /// Replaces the complete backend-owned filter shape and reloads it.
  Future<void> setFilters(LibraryFilter filters) {
    _searchTimer?.cancel();
    _requestToken++;
    _state = _state.copyWith(
      filters: filters,
      games: const <GameLibraryRow>[],
      nextCursor: null,
      facets: null,
      phase: _isReady ? LibraryLoadPhase.loading : LibraryLoadPhase.preReady,
      refreshing: false,
      loadingMore: false,
      lastFailure: null,
    );
    _notify();
    return _load();
  }

  /// Replaces the backend-owned sort shape and reloads it from page one.
  Future<void> setSort(LibrarySort sort) {
    _searchTimer?.cancel();
    _requestToken++;
    _state = _state.copyWith(
      sort: sort,
      games: const <GameLibraryRow>[],
      nextCursor: null,
      facets: null,
      phase: _isReady ? LibraryLoadPhase.loading : LibraryLoadPhase.preReady,
      refreshing: false,
      loadingMore: false,
      lastFailure: null,
    );
    _notify();
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

    _requestInFlight = true;
    final token = ++_requestToken;
    final cursor = loadMore ? _state.nextCursor : null;
    final request = ListGamesRequest(
      scope: _scope,
      searchText: _state.searchText,
      filters: _state.filters,
      sort: _state.sort,
      cursor: cursor,
      pageSize: pageSize,
    );
    final hadRows = _state.games.isNotEmpty;
    _state = _state.copyWith(
      phase: loadMore ? _state.phase : LibraryLoadPhase.loading,
      refreshing: !loadMore && hadRows,
      loadingMore: loadMore,
      lastFailure: null,
    );
    _notify();

    try {
      final page = await reads.listGames(request);
      LibraryFacets? facets;
      LibraryRootPage? roots;
      if (!loadMore) {
        facets = await reads.getLibraryFacets(
          LibraryFacetQuery(
            scope: _scope,
            searchText: _state.searchText,
            filters: _state.filters,
          ),
        );
        if (_scope is LibraryScopeAll) {
          roots = await sources.listLibraryRoots(offset: 0, pageSize: pageSize);
        }
      }
      if (!_canPublish(token)) return;
      final rows = loadMore ? [..._state.games, ...page.items] : page.items;
      _state = _state.copyWith(
        games: List.unmodifiable(rows),
        nextCursor: page.nextCursor,
        facets: loadMore ? _state.facets : facets,
        roots: loadMore ? _state.roots : roots,
        phase: LibraryLoadPhase.ready,
        refreshing: false,
        loadingMore: false,
        lastFailure: null,
      );
      _notify();
    } on ClientFailure catch (failure) {
      if (!_canPublish(token)) return;
      _state = _state.copyWith(
        phase: _state.games.isEmpty
            ? LibraryLoadPhase.failed
            : LibraryLoadPhase.ready,
        refreshing: false,
        loadingMore: false,
        lastFailure: failure,
      );
      _notify();
    } catch (error, stackTrace) {
      if (!_canPublish(token)) return;
      _state = _state.copyWith(
        phase: _state.games.isEmpty
            ? LibraryLoadPhase.failed
            : LibraryLoadPhase.ready,
        refreshing: false,
        loadingMore: false,
        lastFailure: TransportFailure(
          'The Library query failed',
          kind: TransportFailureKind.unexpectedTransportFailure,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
      _notify();
    } finally {
      _requestInFlight = false;
      if (!_disposed && _reloadAfterRequest) {
        _reloadAfterRequest = false;
        unawaited(_load());
      }
    }
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
