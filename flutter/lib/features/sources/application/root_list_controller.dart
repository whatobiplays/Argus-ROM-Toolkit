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
    required SourcesScanAllStatus scanAllStatus,
  }) = SourcesRootListStateReady;
}

extension SourcesRootListStateReadyDetails on SourcesRootListStateReady {
  /// Whether authoritative `totalCount` exceeds the currently loaded roots.
  bool get hasMore => roots.length < totalCount;
}

/// Operation-local Scan All initiation and synchronization state.
///
/// Sources never owns full multi-root job detail; `admitted` carries only the
/// concise feedback needed to stay on Sources and hand the user to Jobs.
@freezed
sealed class SourcesScanAllStatus with _$SourcesScanAllStatus {
  const factory SourcesScanAllStatus.idle() = SourcesScanAllStatusIdle;

  const factory SourcesScanAllStatus.submitting() =
      SourcesScanAllStatusSubmitting;

  const factory SourcesScanAllStatus.admitted({
    required int admittedCount,
    required bool hasExclusions,
    required JobRunId jobRunId,
  }) = SourcesScanAllStatusAdmitted;

  const factory SourcesScanAllStatus.nothingEligible({
    required List<LibraryScanAdmissionExclusion> exclusions,
  }) = SourcesScanAllStatusNothingEligible;

  /// The transport outcome is uncertain and a conflicting submission is
  /// blocked until an authoritative request-identity reconciliation resolves.
  const factory SourcesScanAllStatus.uncertain() =
      SourcesScanAllStatusUncertain;
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
  ScanAllRequestIdentity? _scanAllIdentity;

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

  /// Starts one global Scan All over the authoritative configured-root set.
  ///
  /// The client request identity is generated once per runtime generation and
  /// retained across transport-ambiguous reconciliation so a conflicting
  /// submission can never blindly replay a second Scan All mutation. While
  /// the outcome is uncertain, further submission stays blocked.
  Future<void> startScanAll() async {
    final runtimeId = _activeRuntimeInstanceId;
    if (runtimeId == null) return;
    final current = state.value;
    if (current is! SourcesRootListStateReady) return;
    if (current.scanAllStatus is SourcesScanAllStatusSubmitting ||
        current.scanAllStatus is SourcesScanAllStatusUncertain) {
      return;
    }
    final identity = _scanAllIdentity ??= ScanAllRequestIdentity(
      'scan-all-${runtimeId.value}-${DateTime.now().millisecondsSinceEpoch}',
    );
    _setScanAllStatus(const SourcesScanAllStatus.submitting());
    try {
      final result = await ref
          .read(sourcesApiProvider)
          .startLibraryScanAll(identity);
      final latest = state.value;
      if (latest is! SourcesRootListStateReady) return;
      switch (result) {
        case StartLibraryScanAllResultAdmitted(
          :final handle,
          :final admittedRoots,
          :final exclusions,
        ):
          _setScanAllStatus(
            SourcesScanAllStatus.admitted(
              admittedCount: admittedRoots.length,
              hasExclusions: exclusions.isNotEmpty,
              jobRunId: handle.jobRunId,
            ),
          );
        case StartLibraryScanAllResultNothingEligible(:final exclusions):
          _setScanAllStatus(
            SourcesScanAllStatus.nothingEligible(exclusions: exclusions),
          );
      }
      await _loadAuthoritative();
    } on ClientFailure catch (failure) {
      final latest = state.value;
      if (latest is! SourcesRootListStateReady) return;
      if (failure is TransportFailure) {
        _setScanAllStatus(const SourcesScanAllStatus.uncertain());
        await _reconcileScanAllIdentity(identity);
        return;
      }
      _setScanAllStatus(const SourcesScanAllStatus.idle());
      _setState(AsyncData(latest.copyWith(lastFailure: failure)));
    }
  }

  /// Reconciles an ambiguous Scan All outcome through the authoritative
  /// request-identity lookup without replaying the mutation.
  Future<void> _reconcileScanAllIdentity(
    ScanAllRequestIdentity identity,
  ) async {
    try {
      final resolution = await ref
          .read(sourcesJobsApiProvider)
          .resolveScanAllRequest(identity);
      final latest = state.value;
      if (latest is! SourcesRootListStateReady) return;
      switch (resolution) {
        case LibraryScanAllRequestResolutionAdmitted(
          :final handle,
          :final admittedRoots,
          :final exclusions,
        ):
          _setScanAllStatus(
            SourcesScanAllStatus.admitted(
              admittedCount: admittedRoots.length,
              hasExclusions: exclusions.isNotEmpty,
              jobRunId: handle.jobRunId,
            ),
          );
        case LibraryScanAllRequestResolutionNothingAdmitted():
          _setScanAllStatus(const SourcesScanAllStatus.idle());
      }
      await _loadAuthoritative();
    } on ClientFailure {
      // Stay uncertain: a conflicting submission remains blocked until a
      // later authoritative reconciliation succeeds.
    }
  }

  void _setScanAllStatus(SourcesScanAllStatus status) {
    final current = state.value;
    if (current is! SourcesRootListStateReady) return;
    _setState(AsyncData(current.copyWith(scanAllStatus: status)));
  }

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
      if (!ref.mounted ||
          token != _loadToken ||
          runtimeId != _activeRuntimeInstanceId) {
        return;
      }
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
        scanAllStatus: current is SourcesRootListStateReady
            ? current.scanAllStatus
            : const SourcesScanAllStatus.idle(),
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
        case SourcesReconciliationDemandSourceChanged():
          // Source scopes are owned by the hierarchy controller.
          break;
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
      scanAllStatus: ready.scanAllStatus,
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
      scanAllStatus: ready.scanAllStatus,
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
