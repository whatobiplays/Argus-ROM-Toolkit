import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'library_state.freezed.dart';

/// Runtime generation that owns Library query authority.
@freezed
sealed class LibraryRuntimeContext with _$LibraryRuntimeContext {
  const factory LibraryRuntimeContext.preReady() =
      LibraryRuntimeContextPreReady;

  const factory LibraryRuntimeContext.ready({
    required RuntimeInstanceId runtimeInstanceId,
  }) = LibraryRuntimeContextReady;
}

/// Narrow invalidation signal for Library reconciliation.
@freezed
sealed class LibraryReconciliationDemand with _$LibraryReconciliationDemand {
  const factory LibraryReconciliationDemand.listChanged() =
      LibraryReconciliationDemandListChanged;

  const factory LibraryReconciliationDemand.detailChanged({
    required GameId gameId,
  }) = LibraryReconciliationDemandDetailChanged;
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
@freezed
sealed class LibraryState with _$LibraryState {
  const LibraryState._();

  const factory LibraryState({
    required LibraryScope scope,
    required String? searchText,
    required LibraryFilter filters,
    required LibrarySort sort,
    required List<GameLibraryRow> games,
    required String? nextCursor,
    required LibraryFacets? facets,
    required LibraryRootPage? roots,
    required LibraryLoadPhase phase,
    required bool refreshing,
    required bool loadingMore,
    required ClientFailure? lastFailure,
    required Set<GameId> selectedGameIds,
    required LibraryViewMode viewMode,
    required double gridScrollOffset,
    required double listScrollOffset,
  }) = _LibraryState;

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

  /// Returns the offset for the currently selected presentation mode.
  double get scrollOffset =>
      viewMode == LibraryViewMode.grid ? gridScrollOffset : listScrollOffset;

  bool get hasMore => nextCursor != null;
}
