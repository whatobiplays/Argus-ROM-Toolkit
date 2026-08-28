import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../sources_composition.dart';
import 'sources_state.dart';

part 'local_filesystem_browser_controller.freezed.dart';
part 'local_filesystem_browser_controller.g.dart';

/// Current Argus-owned local-filesystem browser state.
@freezed
sealed class LocalFilesystemBrowserState with _$LocalFilesystemBrowserState {
  const factory LocalFilesystemBrowserState.ready({
    required List<LocalFilesystemBrowseRoot> roots,
    required LocalFilesystemBrowsePage? page,
    required bool loading,
    required bool loadingMore,
    required ClientFailure? failure,
  }) = LocalFilesystemBrowserStateReady;
}

/// Owns browse navigation while retaining provider-issued identities and
/// cursors exactly as returned by the Sources API.
@riverpod
class LocalFilesystemBrowserController
    extends _$LocalFilesystemBrowserController {
  static const int _pageSize = 100;

  _BrowserRequest? _failedRequest;
  int _demandToken = 0;
  StreamSubscription<SourcesReconciliationDemand>? _demandSubscription;

  @override
  LocalFilesystemBrowserState build() {
    ref.onDispose(() {
      _demandToken++;
      unawaited(_demandSubscription?.cancel());
    });
    _subscribeToDemandSource(ref.watch(sourcesReconciliationDemandProvider));
    return const LocalFilesystemBrowserState.ready(
      roots: [],
      page: null,
      loading: false,
      loadingMore: false,
      failure: null,
    );
  }

  /// Loads the current mounted-volume list.
  Future<void> load() async {
    if (state.loading || state.loadingMore) return;
    _failedRequest = const _BrowserRequest.roots();
    state = state.copyWith(loading: true, failure: null);
    try {
      final roots = await ref
          .read(sourcesApiProvider)
          .listLocalFilesystemBrowseRoots();
      _failedRequest = null;
      state = state.copyWith(
        roots: List<LocalFilesystemBrowseRoot>.unmodifiable(roots),
        page: null,
        loading: false,
        failure: null,
      );
    } catch (error, stackTrace) {
      state = state.copyWith(
        loading: false,
        failure: _asFailure(error, stackTrace),
      );
    }
  }

  /// Re-reads the current browser location without discarding it.
  Future<void> refresh() async {
    final page = state.page;
    if (page == null) {
      await load();
      return;
    }
    await _loadPage(page.current.location, cursor: null, append: false);
  }

  /// Opens one provider-issued volume root.
  Future<void> openRoot(LocalFilesystemBrowseRoot root) =>
      _loadPage(root.location, cursor: null, append: false);

  /// Opens one provider-issued direct-child directory.
  Future<void> openDirectory(LocalFilesystemBrowseDirectory directory) =>
      _loadPage(directory.location, cursor: null, append: false);

  /// Moves up using the provider-generated breadcrumb immediately above the
  /// current location. At a volume root, returns to the volume list.
  Future<bool> back() async {
    final page = state.page;
    if (page == null) return false;
    if (page.breadcrumbs.length <= 1) {
      _failedRequest = null;
      state = state.copyWith(page: null, failure: null);
      return true;
    }
    final parent = page.breadcrumbs[page.breadcrumbs.length - 2];
    await _loadPage(parent.location, cursor: null, append: false);
    return true;
  }

  /// Loads the next page using only the backend cursor.
  Future<void> loadMore() async {
    final page = state.page;
    final cursor = page?.nextCursor;
    if (page == null || cursor == null || state.loading || state.loadingMore) {
      return;
    }
    await _loadPage(page.current.location, cursor: cursor, append: true);
  }

  /// Retries the exact failed root or browse request.
  Future<void> retry() async {
    final request = _failedRequest;
    if (request == null || state.loading || state.loadingMore) return;
    if (request.isRoots) {
      await load();
    } else {
      await _loadPage(
        request.location!,
        cursor: request.cursor,
        append: request.append,
      );
    }
  }

  Future<void> _loadPage(
    LocalFilesystemBrowseLocation location, {
    required String? cursor,
    required bool append,
  }) async {
    if (state.loading || state.loadingMore) return;
    final request = _BrowserRequest.browse(
      location: location,
      cursor: cursor,
      append: append,
    );
    _failedRequest = request;
    state = state.copyWith(
      loading: !append,
      loadingMore: append,
      failure: null,
    );
    try {
      final page = await ref
          .read(sourcesApiProvider)
          .listLocalFilesystemBrowseDirectories(
            location: location,
            cursor: cursor,
            pageSize: _pageSize,
          );
      final previous = state.page;
      final combined = append && previous != null
          ? LocalFilesystemBrowsePage(
              current: page.current,
              breadcrumbs: page.breadcrumbs,
              directories: [...previous.directories, ...page.directories],
              nextCursor: page.nextCursor,
            )
          : page;
      _failedRequest = null;
      state = state.copyWith(
        page: combined,
        loading: false,
        loadingMore: false,
        failure: null,
      );
    } catch (error, stackTrace) {
      state = state.copyWith(
        loading: false,
        loadingMore: false,
        failure: _asFailure(error, stackTrace),
      );
    }
  }

  ClientFailure _asFailure(Object error, StackTrace stackTrace) {
    if (error is ClientFailure) return error;
    return TransportFailure(
      'Local filesystem browse failed',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  void _subscribeToDemandSource(SourcesReconciliationDemandSource source) {
    _demandToken++;
    final token = _demandToken;
    final subscription = source.stream.listen((demand) {
      if (token != _demandToken) return;
      if (demand is SourcesReconciliationDemandLifecycleChanged) {
        unawaited(refresh());
      }
    });
    final previous = _demandSubscription;
    _demandSubscription = subscription;
    unawaited(previous?.cancel());
  }
}

final class _BrowserRequest {
  const _BrowserRequest.roots()
    : location = null,
      cursor = null,
      append = false,
      isRoots = true;

  const _BrowserRequest.browse({
    required this.location,
    required this.cursor,
    required this.append,
  }) : isRoots = false;

  final LocalFilesystemBrowseLocation? location;
  final String? cursor;
  final bool append;
  final bool isRoots;
}
