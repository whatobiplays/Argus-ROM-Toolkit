import 'dart:async';

import 'package:argus/core/client/client.dart';

/// Runtime generation that owns Library query authority.
sealed class LibraryRuntimeContext {
  const LibraryRuntimeContext._();

  const factory LibraryRuntimeContext.preReady() =
      LibraryRuntimeContextPreReady;

  const factory LibraryRuntimeContext.ready({
    required RuntimeInstanceId runtimeInstanceId,
  }) = LibraryRuntimeContextReady;
}

final class LibraryRuntimeContextPreReady extends LibraryRuntimeContext {
  const LibraryRuntimeContextPreReady() : super._();
}

final class LibraryRuntimeContextReady extends LibraryRuntimeContext {
  const LibraryRuntimeContextReady({required this.runtimeInstanceId})
    : super._();

  final RuntimeInstanceId runtimeInstanceId;
}

/// Narrow invalidation signal for Library reconciliation.
sealed class LibraryReconciliationDemand {
  const LibraryReconciliationDemand._();

  const factory LibraryReconciliationDemand.listChanged() =
      LibraryReconciliationDemandListChanged;

  const factory LibraryReconciliationDemand.detailChanged({
    required GameId gameId,
  }) = LibraryReconciliationDemandDetailChanged;
}

final class LibraryReconciliationDemandListChanged
    extends LibraryReconciliationDemand {
  const LibraryReconciliationDemandListChanged() : super._();
}

final class LibraryReconciliationDemandDetailChanged
    extends LibraryReconciliationDemand {
  const LibraryReconciliationDemandDetailChanged({required this.gameId})
    : super._();

  final GameId gameId;
}

/// App-composition-owned invalidation stream exposed to the Library feature.
final class LibraryReconciliationDemandSource {
  const LibraryReconciliationDemandSource(this.stream);

  final Stream<LibraryReconciliationDemand> stream;
}

/// Presentation-only arrangement of the bounded Library result set.
enum LibraryViewMode { grid, list }

/// Lifecycle of the latest authoritative Library query.
enum LibraryLoadPhase { preReady, loading, ready, failed }

/// Immutable controller snapshot for one route-owned Library scope.
final class LibraryState {
  const LibraryState({
    required this.scope,
    required this.searchText,
    required this.filters,
    required this.sort,
    required this.games,
    required this.nextCursor,
    required this.facets,
    required this.roots,
    required this.phase,
    required this.refreshing,
    required this.loadingMore,
    required this.lastFailure,
    required this.selectedGameIds,
    required this.viewMode,
    required this.gridScrollOffset,
    required this.listScrollOffset,
  });

  factory LibraryState.initial(LibraryScope scope) => LibraryState(
    scope: scope,
    searchText: null,
    filters: const LibraryFilter(),
    sort: const LibrarySort(),
    games: const <GameLibraryRow>[],
    nextCursor: null,
    facets: null,
    roots: null,
    phase: LibraryLoadPhase.preReady,
    refreshing: false,
    loadingMore: false,
    lastFailure: null,
    selectedGameIds: const <GameId>{},
    viewMode: LibraryViewMode.grid,
    gridScrollOffset: 0,
    listScrollOffset: 0,
  );

  static const Object _notProvided = Object();

  final LibraryScope scope;
  final String? searchText;
  final LibraryFilter filters;
  final LibrarySort sort;
  final List<GameLibraryRow> games;
  final String? nextCursor;
  final LibraryFacets? facets;
  final LibraryRootPage? roots;
  final LibraryLoadPhase phase;
  final bool refreshing;
  final bool loadingMore;
  final ClientFailure? lastFailure;
  final Set<GameId> selectedGameIds;
  final LibraryViewMode viewMode;
  final double gridScrollOffset;
  final double listScrollOffset;

  /// Returns the offset for the currently selected presentation mode.
  double get scrollOffset =>
      viewMode == LibraryViewMode.grid ? gridScrollOffset : listScrollOffset;

  bool get hasMore => nextCursor != null;

  LibraryState copyWith({
    LibraryScope? scope,
    Object? searchText = _notProvided,
    LibraryFilter? filters,
    LibrarySort? sort,
    List<GameLibraryRow>? games,
    Object? nextCursor = _notProvided,
    Object? facets = _notProvided,
    Object? roots = _notProvided,
    LibraryLoadPhase? phase,
    bool? refreshing,
    bool? loadingMore,
    Object? lastFailure = _notProvided,
    Set<GameId>? selectedGameIds,
    LibraryViewMode? viewMode,
    double? gridScrollOffset,
    double? listScrollOffset,
    double? scrollOffset,
  }) => LibraryState(
    scope: scope ?? this.scope,
    searchText: identical(searchText, _notProvided)
        ? this.searchText
        : searchText as String?,
    filters: filters ?? this.filters,
    sort: sort ?? this.sort,
    games: games ?? this.games,
    nextCursor: identical(nextCursor, _notProvided)
        ? this.nextCursor
        : nextCursor as String?,
    facets: identical(facets, _notProvided)
        ? this.facets
        : facets as LibraryFacets?,
    roots: identical(roots, _notProvided)
        ? this.roots
        : roots as LibraryRootPage?,
    phase: phase ?? this.phase,
    refreshing: refreshing ?? this.refreshing,
    loadingMore: loadingMore ?? this.loadingMore,
    lastFailure: identical(lastFailure, _notProvided)
        ? this.lastFailure
        : lastFailure as ClientFailure?,
    selectedGameIds: selectedGameIds ?? this.selectedGameIds,
    viewMode: viewMode ?? this.viewMode,
    gridScrollOffset:
        gridScrollOffset ??
        (scrollOffset != null &&
                (viewMode ?? this.viewMode) == LibraryViewMode.grid
            ? scrollOffset
            : this.gridScrollOffset),
    listScrollOffset:
        listScrollOffset ??
        (scrollOffset != null &&
                (viewMode ?? this.viewMode) == LibraryViewMode.list
            ? scrollOffset
            : this.listScrollOffset),
  );
}
