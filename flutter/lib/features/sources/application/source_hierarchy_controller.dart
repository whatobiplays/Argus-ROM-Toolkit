import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../sources_composition.dart';
import 'source_hierarchy_state.dart';
import 'sources_state.dart';

part 'source_hierarchy_controller.g.dart';

const String _rootScopeKey = '';

enum _ValidationOutcome { present, removed, failed }

/// Query-authoritative incremental hierarchy controller keyed by root.
///
/// It owns bounded per-parent page caches plus transient expansion, selection,
/// and Compact drill-down state. Events are invalidation hints only; every
/// confirmed value comes from a successful focused authoritative read scoped
/// to the current runtime generation.
@Riverpod(keepAlive: true)
class SourceHierarchyController extends _$SourceHierarchyController {
  /// Per-batch bound for focused transient-identity validation. More than this
  /// many identities are processed across multiple bounded batches; the bound
  /// is not a permanent cap on reconciliation.
  static const int maxTransientValidationsPerReconcile = 8;

  static const String _sourceEntryNotFoundCode =
      'ARGUS.V1.CONFIGURATION.SOURCE_ENTRY_NOT_FOUND';

  /// Controller-wide runtime/root generation. Results from an older runtime
  /// or root generation are never published.
  int _generation = 0;

  /// Per-parent page-operation generation. Starting a page-one load/refresh
  /// for one parent supersedes only that parent's older in-flight page work;
  /// independent parents never invalidate each other.
  final Map<String, int> _scopeRequestTokens = {};
  int _demandToken = 0;
  StreamSubscription<SourcesReconciliationDemand>? _demandSubscription;
  SourcesRuntimeContext? _lastRuntimeContext;
  bool _broadRefreshPending = false;
  bool _validationInFlight = false;
  int _validationRunToken = 0;
  final List<SourceEntryId> _validationQueue = [];
  final Set<String> _validatedPresentInGeneration = {};
  SourceHierarchyState? _lastPublished;
  AsyncValue<SourceHierarchyState>? _lastBuildValue;
  Future<void>? _rootScopeLoadInFlight;
  LibraryRootId? _rootScopeLoadRootId;
  int? _rootScopeLoadGeneration;

  @override
  AsyncValue<SourceHierarchyState> build(LibraryRootId rootId) {
    ref.onDispose(() {
      _generation++;
      _scopeRequestTokens.clear();
      _demandToken++;
      _demandSubscription?.cancel();
    });
    final demandSource = ref.watch(sourcesReconciliationDemandProvider);
    _subscribeToDemandSource(demandSource, rootId);
    final context = ref.watch(sourcesRuntimeContextProvider);
    final previous = _lastRuntimeContext;
    _lastRuntimeContext = context;
    if (previous != null && previous != context) {
      // Runtime replacement: preserve last-confirmed state, invalidate all
      // in-flight work from the old generation, and authoritatively reconcile
      // every loaded scope under the new runtime. This is the canonical
      // replacement path; it never depends on the coordinator's tracked roots.
      _generation++;
      _scopeRequestTokens.clear();
      _broadRefreshPending = false;
      _validatedPresentInGeneration.clear();
      final current = _lastPublished;
      if (current != null && current.rootId == rootId) {
        // Reset in-flight scope flags so the new generation's broad refresh is
        // not suppressed by work that belonged to the replaced runtime.
        _lastPublished = current.copyWith(
          reconciling: false,
          scopesByParent: {
            for (final entry in current.scopesByParent.entries)
              entry.key: entry.value.copyWith(
                refreshing: false,
                loadingFirstPage: false,
                loadingMore: false,
              ),
          },
        );
        _lastBuildValue = AsyncValue.data(_lastPublished!);
      }
      scheduleMicrotask(() => unawaited(reconcile(rootId)));
      return _lastBuildValue ?? const AsyncLoading();
    }
    if (_lastPublished != null && _lastPublished!.rootId == rootId) {
      return _lastBuildValue ?? const AsyncLoading();
    }
    if (_lastBuildValue case final AsyncError<SourceHierarchyState> error
        when _lastRuntimeContext == context) {
      return error;
    }
    _generation++;
    scheduleMicrotask(() => unawaited(_loadRootScope(rootId)));
    return const AsyncLoading();
  }

  int _beginParentRequest(String parentKey) {
    final next = (_scopeRequestTokens[parentKey] ?? 0) + 1;
    _scopeRequestTokens[parentKey] = next;
    return next;
  }

  bool _isParentRequestStale(
    int generation,
    int parentToken,
    String parentKey,
  ) =>
      generation != _generation ||
      !ref.mounted ||
      parentToken != (_scopeRequestTokens[parentKey] ?? 0);

  /// Reconciles all loaded scopes from page one, or performs the initial root
  /// load when nothing has loaded yet.
  Future<void> refresh(LibraryRootId rootId) async {
    if (!ref.mounted) return;
    final current = _lastPublished;
    if (current == null ||
        current.rootId != rootId ||
        current.scopesByParent.isEmpty) {
      await _loadRootScope(rootId);
      return;
    }
    await reconcile(rootId);
  }

  /// Broad authoritative refresh of every loaded scope, preserving confirmed
  /// content while pending and replacing each scope's cursor chain only on
  /// success. Compatible demands coalesce into one pending broad refresh.
  Future<void> reconcile(LibraryRootId rootId) async {
    if (!ref.mounted) return;
    final current = _lastPublished;
    if (current == null || current.rootId != rootId || _broadRefreshPending) {
      return;
    }
    _broadRefreshPending = true;
    final keys = current.scopesByParent.keys.toList();
    _publish(current.copyWith(reconciling: true));
    try {
      await Future.wait([for (final key in keys) _refreshScope(rootId, key)]);
    } finally {
      _broadRefreshPending = false;
      if (ref.mounted) {
        final latest = _lastPublished;
        if (latest != null && latest.rootId == rootId) {
          _publish(latest.copyWith(reconciling: false));
        }
      }
    }
    await _reconcileTransientIdentities(rootId);
  }

  /// Expands one container: adds stable expansion state immediately and loads
  /// only that parent's first page when not already loaded.
  Future<void> expand(LibraryRootId rootId, SourceEntryId entryId) async {
    if (!ref.mounted) return;
    final current = _lastPublished;
    if (current == null || current.rootId != rootId) return;
    final key = entryId.value;
    final wasExpanded = current.expandedEntryIds.contains(key);
    _publish(
      current.copyWith(expandedEntryIds: {...current.expandedEntryIds, key}),
    );
    if (!wasExpanded) {
      await _loadFirstPageForParent(rootId, key);
    }
  }

  /// Collapses one entry, keeping its loaded page cache for the controller
  /// lifetime.
  Future<void> collapse(LibraryRootId rootId, SourceEntryId entryId) async {
    if (!ref.mounted) return;
    final current = _lastPublished;
    if (current == null || current.rootId != rootId) return;
    _publish(
      current.copyWith(
        expandedEntryIds: {...current.expandedEntryIds}..remove(entryId.value),
      ),
    );
  }

  /// Appends the next authoritative page for one parent scope.
  Future<void> loadMore(LibraryRootId rootId, String parentKey) async {
    if (!ref.mounted) return;
    final current = _lastPublished;
    if (current == null || current.rootId != rootId) return;
    final scope = current.scopesByParent[parentKey];
    if (scope == null ||
        !scope.hasLoaded ||
        scope.nextCursor == null ||
        scope.loadingMore ||
        scope.refreshing) {
      return;
    }
    final generation = _generation;
    // loadMore does NOT advance the parent request generation: it appends to
    // the currently confirmed cursor chain. A newer page-one operation for the
    // same parent will advance that generation and supersede this result.
    final parentToken = _scopeRequestTokens[parentKey] ?? 0;
    final cursor = scope.nextCursor;
    _publish(
      current.copyWith(
        scopesByParent: {
          ...current.scopesByParent,
          parentKey: scope.copyWith(loadingMore: true, failure: null),
        },
      ),
    );
    try {
      final page = await _listChildren(rootId, parentKey, cursor);
      if (_isParentRequestStale(generation, parentToken, parentKey)) return;
      final latest = _lastPublished;
      if (latest == null || latest.rootId != rootId) return;
      final existing = latest.scopesByParent[parentKey];
      if (existing == null || existing.nextCursor != cursor) return;
      _publish(
        latest.copyWith(
          scopesByParent: {
            ...latest.scopesByParent,
            parentKey: existing.copyWith(
              children: [...existing.children, ...page.items],
              nextCursor: page.nextCursor,
              loadingMore: false,
            ),
          },
        ),
      );
    } on ClientFailure catch (failure) {
      if (_isParentRequestStale(generation, parentToken, parentKey)) return;
      final latest = _lastPublished;
      if (latest == null || latest.rootId != rootId) return;
      final existing = latest.scopesByParent[parentKey];
      if (existing == null || existing.nextCursor != cursor) return;
      _publish(
        latest.copyWith(
          scopesByParent: {
            ...latest.scopesByParent,
            parentKey: existing.copyWith(loadingMore: false, failure: failure),
          },
        ),
      );
    }
  }

  /// Retries the failed operation for one parent scope: page one when the
  /// first page never loaded, otherwise the stored next cursor.
  Future<void> retry(LibraryRootId rootId, String parentKey) async {
    if (!ref.mounted) return;
    final current = _lastPublished;
    if (current == null || current.rootId != rootId) return;
    final scope = current.scopesByParent[parentKey];
    if (scope == null || scope.failure == null) return;
    if (scope.loadingFirstPage || scope.loadingMore || scope.refreshing) return;
    if (scope.hasLoaded) {
      await loadMore(rootId, parentKey);
    } else if (parentKey == _rootScopeKey) {
      await _loadRootScope(rootId);
    } else {
      await _loadFirstPageForParent(rootId, parentKey);
    }
  }

  /// Selects one entry as transient feature state; never route state.
  Future<void> select(LibraryRootId rootId, SourceEntryId entryId) async {
    if (!ref.mounted) return;
    final current = _lastPublished;
    if (current == null || current.rootId != rootId) return;
    _publish(current.copyWith(selectedEntryId: entryId));
  }

  /// Advances the Compact drill-down path to one container.
  Future<void> openContainer(
    LibraryRootId rootId,
    SourceEntryId entryId,
  ) async {
    if (!ref.mounted) return;
    final current = _lastPublished;
    if (current == null || current.rootId != rootId) return;
    if (!current.compactDrillDownPath.contains(entryId)) {
      _publish(
        current.copyWith(
          compactDrillDownPath: [...current.compactDrillDownPath, entryId],
        ),
      );
    }
    await expand(rootId, entryId);
  }

  /// Pops the Compact drill-down path toward the root.
  Future<void> goBack(LibraryRootId rootId) async {
    if (!ref.mounted) return;
    final current = _lastPublished;
    if (current == null || current.rootId != rootId) return;
    if (current.compactDrillDownPath.isEmpty) return;
    _publish(
      current.copyWith(
        compactDrillDownPath: [...current.compactDrillDownPath]..removeLast(),
      ),
    );
  }

  Future<void> _loadRootScope(LibraryRootId rootId) async {
    if (!ref.mounted) return;
    final pending = _rootScopeLoadInFlight;
    if (pending != null &&
        _rootScopeLoadRootId == rootId &&
        _rootScopeLoadGeneration == _generation) {
      await pending;
      return;
    }
    final requestGeneration = _generation;
    final request = _loadRootScopeRequest(rootId);
    _rootScopeLoadInFlight = request;
    _rootScopeLoadRootId = rootId;
    _rootScopeLoadGeneration = requestGeneration;
    try {
      await request;
    } finally {
      if (identical(_rootScopeLoadInFlight, request)) {
        _rootScopeLoadInFlight = null;
        _rootScopeLoadRootId = null;
        _rootScopeLoadGeneration = null;
      }
    }
  }

  Future<void> _loadRootScopeRequest(LibraryRootId rootId) async {
    if (!ref.mounted) return;
    final generation = _generation;
    final parentToken = _beginParentRequest(_rootScopeKey);
    try {
      final page = await _listChildren(rootId, _rootScopeKey, null);
      if (_isParentRequestStale(generation, parentToken, _rootScopeKey)) {
        return;
      }
      final current = _lastPublished;
      if (current != null && current.rootId != rootId) return;
      _publish(
        SourceHierarchyState(
          rootId: rootId,
          scopesByParent: {
            _rootScopeKey: ParentScopeState(
              children: page.items,
              nextCursor: page.nextCursor,
              hasLoaded: true,
              loadingFirstPage: false,
              loadingMore: false,
              refreshing: false,
            ),
          },
          expandedEntryIds: const {},
          compactDrillDownPath: const [],
          reconciling: false,
        ),
      );
    } on ClientFailure catch (failure, stackTrace) {
      if (_isParentRequestStale(generation, parentToken, _rootScopeKey)) {
        return;
      }
      _lastPublished = null;
      _lastBuildValue = AsyncError(failure, stackTrace);
      state = _lastBuildValue!;
    }
  }

  Future<void> _loadFirstPageForParent(
    LibraryRootId rootId,
    String parentKey,
  ) async {
    if (!ref.mounted) return;
    final current = _lastPublished;
    if (current == null || current.rootId != rootId) return;
    final scope = current.scopesByParent[parentKey];
    if (scope != null && (scope.hasLoaded || scope.loadingFirstPage)) return;
    final generation = _generation;
    final parentToken = _beginParentRequest(parentKey);
    _publish(
      current.copyWith(
        scopesByParent: {
          ...current.scopesByParent,
          parentKey:
              (scope ??
                      const ParentScopeState(
                        children: [],
                        hasLoaded: false,
                        loadingFirstPage: false,
                        loadingMore: false,
                        refreshing: false,
                      ))
                  .copyWith(loadingFirstPage: true, loadingMore: false),
        },
      ),
    );
    try {
      final page = await _listChildren(rootId, parentKey, null);
      if (_isParentRequestStale(generation, parentToken, parentKey)) return;
      final latest = _lastPublished;
      if (latest == null || latest.rootId != rootId) return;
      _publish(
        latest.copyWith(
          scopesByParent: {
            ...latest.scopesByParent,
            parentKey: ParentScopeState(
              children: page.items,
              nextCursor: page.nextCursor,
              hasLoaded: true,
              loadingFirstPage: false,
              loadingMore: false,
              refreshing: false,
            ),
          },
        ),
      );
    } on ClientFailure catch (failure) {
      if (_isParentRequestStale(generation, parentToken, parentKey)) return;
      final latest = _lastPublished;
      if (latest == null || latest.rootId != rootId) return;
      final existing = latest.scopesByParent[parentKey];
      if (existing == null) return;
      _publish(
        latest.copyWith(
          scopesByParent: {
            ...latest.scopesByParent,
            parentKey: existing.copyWith(
              loadingFirstPage: false,
              failure: failure,
            ),
          },
        ),
      );
    }
  }

  /// Authoritatively refreshes one loaded scope from page one. Confirmed
  /// children stay visible while pending; the cursor chain is replaced only
  /// after success. Absence from the refreshed page never proves deletion.
  Future<void> _refreshScope(LibraryRootId rootId, String parentKey) async {
    if (!ref.mounted) return;
    final current = _lastPublished;
    if (current == null || current.rootId != rootId) return;
    final scope = current.scopesByParent[parentKey];
    if (scope == null || !scope.hasLoaded || scope.refreshing) return;
    final generation = _generation;
    // A page-one refresh supersedes older page work for THIS parent only.
    final parentToken = _beginParentRequest(parentKey);
    _publish(
      current.copyWith(
        scopesByParent: {
          ...current.scopesByParent,
          parentKey: scope.copyWith(
            refreshing: true,
            failure: null,
            loadingMore: false,
          ),
        },
      ),
    );
    try {
      final page = await _listChildren(rootId, parentKey, null);
      if (_isParentRequestStale(generation, parentToken, parentKey)) return;
      final latest = _lastPublished;
      if (latest == null || latest.rootId != rootId) return;
      final existing = latest.scopesByParent[parentKey];
      if (existing == null) return;
      _publish(
        latest.copyWith(
          scopesByParent: {
            ...latest.scopesByParent,
            parentKey: existing.copyWith(
              children: page.items,
              nextCursor: page.nextCursor,
              refreshing: false,
              hasLoaded: true,
            ),
          },
        ),
      );
      await _reconcileTransientIdentities(rootId);
    } on ClientFailure catch (failure) {
      if (_isParentRequestStale(generation, parentToken, parentKey)) return;
      final latest = _lastPublished;
      if (latest == null || latest.rootId != rootId) return;
      final existing = latest.scopesByParent[parentKey];
      if (existing == null) return;
      _publish(
        latest.copyWith(
          scopesByParent: {
            ...latest.scopesByParent,
            parentKey: existing.copyWith(refreshing: false, failure: failure),
          },
        ),
      );
    }
  }

  void _subscribeToDemandSource(
    SourcesReconciliationDemandSource source,
    LibraryRootId rootId,
  ) {
    _demandToken++;
    final token = _demandToken;
    final subscription = source.stream.listen((demand) {
      if (token != _demandToken || !ref.mounted) return;
      if (demand is SourcesReconciliationDemandLifecycleChanged) {
        unawaited(refresh(rootId));
        return;
      }
      if (demand is! SourcesReconciliationDemandSourceChanged) return;
      if (demand.libraryRootId != rootId) return;
      switch (demand.scope) {
        case SourceEntriesChangeScopeRootChildren():
          unawaited(_refreshScope(rootId, _rootScopeKey));
        case SourceEntriesChangeScopeEntryChildren(:final parentSourceEntryId):
          final key = parentSourceEntryId.value;
          final current = _lastPublished;
          if (current != null && current.scopesByParent.containsKey(key)) {
            unawaited(_refreshScope(rootId, key));
          }
        case SourceEntriesChangeScopeEntireRootHierarchy():
          unawaited(reconcile(rootId));
      }
    });
    final previous = _demandSubscription;
    _demandSubscription = subscription;
    previous?.cancel();
  }

  /// Reconciles transient identities against focused authoritative reads.
  ///
  /// Absence from loaded pages is never treated as deletion. Only a focused
  /// `getSourceEntry` not-found is authoritative removal evidence; any other
  /// failure preserves the identity and does not start a tight retry loop.
  Future<void> _reconcileTransientIdentities(LibraryRootId rootId) async {
    if (!ref.mounted) return;
    final current = _lastPublished;
    if (current == null || current.rootId != rootId) return;
    final loadedIds = <String>{
      for (final scope in current.scopesByParent.values)
        for (final entry in scope.children) entry.sourceEntryId.value,
    };
    final pending = <SourceEntryId>[];
    void addIfAbsent(SourceEntryId id) {
      if (!loadedIds.contains(id.value) &&
          !pending.contains(id) &&
          !_validatedPresentInGeneration.contains(id.value)) {
        pending.add(id);
      }
    }

    final selected = current.selectedEntryId;
    if (selected != null) addIfAbsent(selected);
    for (final id in current.compactDrillDownPath.reversed) {
      addIfAbsent(id);
    }
    for (final key in current.expandedEntryIds) {
      if (!loadedIds.contains(key)) {
        addIfAbsent(SourceEntryId(key));
      }
    }
    if (pending.isEmpty) return;
    _validationQueue
      ..clear()
      ..addAll(pending);
    await _processValidationQueue(rootId);
  }

  Future<void> _processValidationQueue(LibraryRootId rootId) async {
    if (!ref.mounted) return;
    if (_validationInFlight) {
      // A run is already active. Supersede its remaining batches: the old run
      // checks the token at every boundary and exits, and queue items are
      // removed as they are claimed, so no identity is validated twice.
      _validationRunToken++;
    }
    final runToken = _validationRunToken;
    final generation = _generation;
    _validationInFlight = true;
    try {
      while (_validationQueue.isNotEmpty && ref.mounted) {
        if (runToken != _validationRunToken || generation != _generation) {
          return;
        }
        final batch = _validationQueue
            .take(maxTransientValidationsPerReconcile)
            .toList();
        _validationQueue.removeRange(0, batch.length);
        final results = await Future.wait([
          for (final id in batch) _validateIdentity(id),
        ]);
        if (runToken != _validationRunToken ||
            generation != _generation ||
            !ref.mounted) {
          return;
        }
        final removed = <SourceEntryId>[
          for (var index = 0; index < batch.length; index++)
            if (results[index] == _ValidationOutcome.removed) batch[index],
        ];
        if (removed.isNotEmpty) {
          _applyRemovedIdentities(rootId, removed);
        }
        if (_validationQueue.isEmpty) return;
        // Bounded continuation: the per-batch cap is not a permanent cap; keep
        // draining the already-started reconciliation without requiring
        // another backend event, but yield between batches.
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      if (runToken == _validationRunToken) {
        _validationInFlight = false;
      }
    }
  }

  Future<_ValidationOutcome> _validateIdentity(SourceEntryId id) async {
    try {
      await ref.read(sourcesApiProvider).getSourceEntry(id);
      _validatedPresentInGeneration.add(id.value);
      return _ValidationOutcome.present;
    } on ApplicationFailure catch (failure) {
      if (failure.error.code.value == _sourceEntryNotFoundCode) {
        return _ValidationOutcome.removed;
      }
      return _ValidationOutcome.failed;
    } on ClientFailure {
      return _ValidationOutcome.failed;
    }
  }

  void _applyRemovedIdentities(
    LibraryRootId rootId,
    List<SourceEntryId> removed,
  ) {
    final current = _lastPublished;
    if (current == null || current.rootId != rootId) return;
    final removedKeys = {for (final id in removed) id.value};
    var selected = current.selectedEntryId;
    if (selected != null && removedKeys.contains(selected.value)) {
      selected = null;
    }
    final expanded = <String>{...current.expandedEntryIds}
      ..removeAll(removedKeys);
    var path = current.compactDrillDownPath;
    if (path.any((id) => removedKeys.contains(id.value))) {
      final trimmed = <SourceEntryId>[];
      for (final id in path) {
        if (removedKeys.contains(id.value)) break;
        trimmed.add(id);
      }
      path = trimmed;
    }
    _publish(
      current.copyWith(
        selectedEntryId: selected,
        expandedEntryIds: expanded,
        compactDrillDownPath: path,
      ),
    );
  }

  Future<SourceEntryChildrenPage> _listChildren(
    LibraryRootId rootId,
    String parentKey,
    String? cursor, {
    int pageSize = 100,
  }) {
    return ref
        .read(sourcesApiProvider)
        .listSourceEntryChildren(
          libraryRootId: rootId,
          parentSourceEntryId: parentKey.isEmpty
              ? null
              : SourceEntryId(parentKey),
          cursor: cursor,
          pageSize: pageSize,
        );
  }

  void _publish(SourceHierarchyState next) {
    if (!ref.mounted) return;
    _lastPublished = next;
    _lastBuildValue = AsyncValue.data(next);
    state = _lastBuildValue!;
  }
}
