import 'package:argus/core/client/client.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'source_hierarchy_state.freezed.dart';

/// Bounded authoritative cache for exactly one parent scope.
///
/// Loaded pages are NOT complete graph authority: absence from this cache
/// never proves deletion.
@freezed
sealed class ParentScopeState with _$ParentScopeState {
  const factory ParentScopeState({
    required List<SourceEntry> children,
    String? nextCursor,
    required bool hasLoaded,
    required bool loadingFirstPage,
    required bool loadingMore,
    required bool refreshing,
    ClientFailure? failure,
  }) = _ParentScopeState;
}

/// Query-authoritative incremental hierarchy state keyed by routed root.
@freezed
sealed class SourceHierarchyState with _$SourceHierarchyState {
  const factory SourceHierarchyState({
    required LibraryRootId rootId,

    /// Parent scope key: `''` is the root scope, otherwise the parent
    /// `SourceEntryId.value`.
    required Map<String, ParentScopeState> scopesByParent,
    required Set<String> expandedEntryIds,
    SourceEntryId? selectedEntryId,
    required List<SourceEntryId> compactDrillDownPath,
    required bool reconciling,
  }) = _SourceHierarchyState;
}
