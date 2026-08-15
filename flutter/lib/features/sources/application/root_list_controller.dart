import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../sources_composition.dart';
import 'sources_state.dart';

part 'root_list_controller.freezed.dart';
part 'root_list_controller.g.dart';

/// Loaded configured-root list state with confirmed content and a bounded
/// synchronization signal. `refreshing` and `lastFailure` never replace the
/// confirmed roots; only a successful authoritative read changes `roots`.
@freezed
sealed class SourcesRootListState with _$SourcesRootListState {
  const factory SourcesRootListState.ready({
    required List<LibraryRoot> roots,
    required int totalCount,
    required bool refreshing,
    ClientFailure? lastFailure,
    required bool loadingMore,
    required bool loadMoreFailed,
    required int nextOffset,
  }) = SourcesRootListStateReady;
}

extension SourcesRootListStateReadyDetails on SourcesRootListStateReady {
  /// Whether authoritative `totalCount` exceeds the currently loaded roots.
  bool get hasMore => roots.length < totalCount;
}

/// One application-lifetime owner of query-authoritative root-list state.
///
/// The outer [AsyncValue] represents whether usable authority exists: loading
/// until the first read completes, error when that initial read fails, and
/// ready afterwards. Confirmed roots remain renderable during refresh and
/// runtime adoption; only a successful focused read changes them.
@Riverpod(keepAlive: true)
class SourcesRootListController extends _$SourcesRootListController {
  static const int _pageSize = 100;

  SourcesRuntimeContext? _lastRuntimeContext;
  AsyncValue<SourcesRootListState>? _lastBuildValue;
  SourcesRootListState? _lastLoaded;
  RuntimeInstanceId? _activeRuntimeInstanceId;
  int _loadToken = 0;
  bool _loadInFlight = false;
  int _demandToken = 0;
  StreamSubscription<SourcesReconciliationDemand>? _demandSubscription;

  @override
  AsyncValue<SourcesRootListState> build() {
    ref.onDispose(() {
      _demandToken++;
      _demandSubscription?.cancel();
    });
    final demandSource = ref.watch(sourcesReconciliationDemandProvider);
    _subscribeToDemandSource(demandSource);
    final context = ref.watch(sourcesRuntimeContextProvider);
    if (context == _lastRuntimeContext) {
      return _lastBuildValue ?? const AsyncLoading();
    }
    _lastRuntimeContext = context;
    _loadToken++;
    _loadInFlight = false;
    _activeRuntimeInstanceId = switch (context) {
      SourcesRuntimeContextPreReady() => null,
      SourcesRuntimeContextReady(:final runtimeInstanceId) => runtimeInstanceId,
    };
    final retained = _lastLoaded;
    final AsyncValue<SourcesRootListState> result = retained == null
        ? const AsyncLoading()
        : AsyncData(_withRefreshing(retained));
    _lastBuildValue = result;
    scheduleMicrotask(() => unawaited(_loadAuthoritative()));
    return result;
  }

  /// Issues one focused authoritative root-list read.
  Future<void> refresh() => _loadAuthoritative();

  /// Loads the next bounded authoritative page in deterministic order.
  Future<void> loadMore() => _loadAuthoritative(loadMore: true);

  Future<void> _loadAuthoritative({bool loadMore = false}) async {
    final runtimeId = _activeRuntimeInstanceId;
    if (runtimeId == null || _loadInFlight) return;
    final current = state.value;
    if (loadMore) {
      if (current is! SourcesRootListStateReady) return;
      if (current.loadingMore || current.nextOffset >= current.totalCount) {
        return;
      }
    }
    _loadInFlight = true;
    final token = ++_loadToken;
    final api = ref.read(sourcesApiProvider);
    if (loadMore && current is SourcesRootListStateReady) {
      _setState(
        AsyncData(
          current.copyWith(
            loadingMore: true,
            loadMoreFailed: false,
            refreshing: false,
          ),
        ),
      );
    } else if (!loadMore && current is SourcesRootListStateReady) {
      _setState(AsyncData(_withRefreshing(current)));
    }
    try {
      final offset = loadMore
          ? (state.value! as SourcesRootListStateReady).nextOffset
          : 0;
      final page = await api.listLibraryRoots(
        offset: offset,
        pageSize: _pageSize,
      );
      if (token != _loadToken || runtimeId != _activeRuntimeInstanceId) return;
      final latest = state.value;
      if (loadMore && latest is! SourcesRootListStateReady) return;
      final roots = loadMore
          ? _mergeRoots((latest as SourcesRootListStateReady).roots, page.items)
          : page.items;
      final nextOffset = loadMore
          ? (page.items.isEmpty
                ? (latest as SourcesRootListStateReady).totalCount
                : offset + page.items.length)
          : page.items.length;
      final loaded = SourcesRootListState.ready(
        roots: roots,
        totalCount: page.totalCount,
        refreshing: false,
        loadingMore: false,
        loadMoreFailed: false,
        nextOffset: nextOffset,
      );
      _lastLoaded = loaded;
      _setState(AsyncData(loaded));
    } on ClientFailure catch (failure) {
      if (token != _loadToken || runtimeId != _activeRuntimeInstanceId) return;
      final last = _lastLoaded;
      if (last == null) {
        _setState(AsyncError(failure, StackTrace.current));
        return;
      }
      if (loadMore) {
        final ready = last as SourcesRootListStateReady;
        _setState(
          AsyncData(
            ready.copyWith(
              loadingMore: false,
              loadMoreFailed: true,
              lastFailure: failure,
            ),
          ),
        );
      } else {
        _setState(AsyncData(_withFailure(last, failure)));
      }
    } finally {
      if (token == _loadToken) {
        _loadInFlight = false;
      }
    }
  }

  void _subscribeToDemandSource(SourcesReconciliationDemandSource source) {
    _demandToken++;
    final token = _demandToken;
    final subscription = source.stream.listen((demand) {
      if (token != _demandToken) return;
      switch (demand) {
        case SourcesReconciliationDemandRootsChanged():
          unawaited(refresh());
        case SourcesReconciliationDemandRootChanged():
          // A single-root invalidation may still change list projections or
          // ordering; one focused list refresh covers it.
          unawaited(refresh());
      }
    });
    final previous = _demandSubscription;
    _demandSubscription = subscription;
    previous?.cancel();
  }

  SourcesRootListState _withRefreshing(SourcesRootListState state) {
    final ready = state as SourcesRootListStateReady;
    return SourcesRootListState.ready(
      roots: ready.roots,
      totalCount: ready.totalCount,
      refreshing: true,
      lastFailure: ready.lastFailure,
      loadingMore: ready.loadingMore,
      loadMoreFailed: ready.loadMoreFailed,
      nextOffset: ready.nextOffset,
    );
  }

  SourcesRootListState _withFailure(
    SourcesRootListState state,
    ClientFailure failure,
  ) {
    final ready = state as SourcesRootListStateReady;
    return SourcesRootListState.ready(
      roots: ready.roots,
      totalCount: ready.totalCount,
      refreshing: false,
      lastFailure: failure,
      loadingMore: ready.loadingMore,
      loadMoreFailed: ready.loadMoreFailed,
      nextOffset: ready.nextOffset,
    );
  }

  List<LibraryRoot> _mergeRoots(
    List<LibraryRoot> existing,
    List<LibraryRoot> incoming,
  ) {
    final seen = existing.map((root) => root.id).toSet();
    return [
      ...existing,
      for (final root in incoming)
        if (!seen.contains(root.id)) root,
    ];
  }

  void _setState(AsyncValue<SourcesRootListState> next) {
    _lastBuildValue = next;
    state = next;
  }
}
