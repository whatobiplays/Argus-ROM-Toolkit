import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../jobs_composition.dart';
import 'jobs_state.dart';

part 'jobs_list_controller.freezed.dart';
part 'jobs_list_controller.g.dart';

/// Query-authoritative Active + Recent Jobs landing state.
@freezed
sealed class JobsListState with _$JobsListState {
  const factory JobsListState.ready({
    required List<JobListItem> activeJobs,
    required List<JobListItem> recentJobs,
    required int recentTotalCount,
    required bool refreshing,
    ClientFailure? lastFailure,
    required bool loadingMore,
    required bool loadMoreFailed,
    int? nextOffset,
  }) = JobsListStateReady;
}

/// One application-lifetime owner of authoritative Jobs list state.
@Riverpod(keepAlive: true)
class JobsListController extends _$JobsListController {
  static const int _pageSize = 20;

  JobsRuntimeContext? _lastRuntimeContext;
  AsyncValue<JobsListState>? _lastBuildValue;
  JobsListState? _lastLoaded;
  RuntimeInstanceId? _activeRuntimeInstanceId;
  int _loadToken = 0;
  bool _loadInFlight = false;
  int _demandToken = 0;
  StreamSubscription<JobsReconciliationDemand>? _demandSubscription;

  @override
  AsyncValue<JobsListState> build() {
    ref.onDispose(() {
      _demandToken++;
      _demandSubscription?.cancel();
    });
    final demandSource = ref.watch(jobsReconciliationDemandProvider);
    _subscribeToDemandSource(demandSource);
    final context = ref.watch(jobsRuntimeContextProvider);
    if (context == _lastRuntimeContext) {
      return _lastBuildValue ?? const AsyncLoading();
    }
    _lastRuntimeContext = context;
    _loadToken++;
    _loadInFlight = false;
    _activeRuntimeInstanceId = switch (context) {
      JobsRuntimeContextPreReady() => null,
      JobsRuntimeContextReady(:final runtimeInstanceId) => runtimeInstanceId,
    };
    final retained = _lastLoaded;
    final result = retained == null
        ? const AsyncLoading<JobsListState>()
        : AsyncData(_withRefreshing(retained));
    _lastBuildValue = result;
    scheduleMicrotask(() => unawaited(_loadAuthoritative()));
    return result;
  }

  Future<void> refresh() => _loadAuthoritative();

  Future<void> loadMore() => _loadAuthoritative(loadMore: true);

  Future<void> _loadAuthoritative({bool loadMore = false}) async {
    final runtimeId = _activeRuntimeInstanceId;
    if (runtimeId == null || _loadInFlight) return;
    final current = state.value;
    if (loadMore) {
      if (current is! JobsListStateReady ||
          current.loadingMore ||
          current.nextOffset == null) {
        return;
      }
    }
    _loadInFlight = true;
    final token = ++_loadToken;
    final api = ref.read(jobsApiProvider);
    if (!loadMore && current is JobsListStateReady) {
      _setState(AsyncData(_withRefreshing(current)));
    } else if (loadMore && current is JobsListStateReady) {
      _setState(
        AsyncData(current.copyWith(loadingMore: true, loadMoreFailed: false)),
      );
    }
    try {
      final active = await api.listActiveJobs();
      final recent = loadMore
          ? await api.listRecentTerminalJobs(
              offset: current!.nextOffset!,
              pageSize: _pageSize,
            )
          : await api.listRecentTerminalJobs(offset: 0, pageSize: _pageSize);
      if (token != _loadToken || runtimeId != _activeRuntimeInstanceId) return;
      final loaded = JobsListState.ready(
        activeJobs: active.items,
        recentJobs: loadMore
            ? _mergeRecent(
                (state.value! as JobsListStateReady).recentJobs,
                recent.items,
              )
            : recent.items,
        recentTotalCount: recent.totalCount,
        refreshing: false,
        loadingMore: false,
        loadMoreFailed: false,
        nextOffset: recent.nextOffset,
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
      _setState(
        AsyncData(
          loadMore && current is JobsListStateReady
              ? last.copyWith(
                  loadingMore: false,
                  loadMoreFailed: true,
                  lastFailure: failure,
                )
              : _withFailure(last, failure),
        ),
      );
    } finally {
      if (token == _loadToken) {
        _loadInFlight = false;
      }
    }
  }

  void _subscribeToDemandSource(JobsReconciliationDemandSource source) {
    _demandToken++;
    final token = _demandToken;
    final subscription = source.stream.listen((demand) {
      if (token != _demandToken) return;
      switch (demand) {
        case JobsReconciliationDemandListChanged():
          unawaited(refresh());
        case JobsReconciliationDemandDetailChanged():
          // List membership/active count may also change; one focused refresh
          // keeps the landing truthful without local lifecycle authority.
          unawaited(refresh());
      }
    });
    final previous = _demandSubscription;
    _demandSubscription = subscription;
    previous?.cancel();
  }

  List<JobListItem> _mergeRecent(
    List<JobListItem> existing,
    List<JobListItem> incoming,
  ) {
    final seen = existing.map((job) => job.jobRunId).toSet();
    return [
      ...existing,
      for (final job in incoming)
        if (!seen.contains(job.jobRunId)) job,
    ];
  }

  JobsListState _withRefreshing(JobsListState state) {
    final ready = state as JobsListStateReady;
    return JobsListState.ready(
      activeJobs: ready.activeJobs,
      recentJobs: ready.recentJobs,
      recentTotalCount: ready.recentTotalCount,
      refreshing: true,
      lastFailure: ready.lastFailure,
      loadingMore: ready.loadingMore,
      loadMoreFailed: ready.loadMoreFailed,
      nextOffset: ready.nextOffset,
    );
  }

  JobsListState _withFailure(JobsListState state, ClientFailure failure) {
    final ready = state as JobsListStateReady;
    return JobsListState.ready(
      activeJobs: ready.activeJobs,
      recentJobs: ready.recentJobs,
      recentTotalCount: ready.recentTotalCount,
      refreshing: false,
      lastFailure: failure,
      loadingMore: ready.loadingMore,
      loadMoreFailed: ready.loadMoreFailed,
      nextOffset: ready.nextOffset,
    );
  }

  void _setState(AsyncValue<JobsListState> next) {
    _lastBuildValue = next;
    state = next;
  }
}
