import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../sources_composition.dart';
import 'sources_state.dart';

part 'root_detail_controller.freezed.dart';
part 'root_detail_controller.g.dart';

/// Loaded root-detail state keyed by the routed root identity.
@freezed
sealed class SourcesRootDetailState with _$SourcesRootDetailState {
  /// The routed root is authoritatively configured.
  const factory SourcesRootDetailState.ready({
    required LibraryRoot root,
    required bool refreshing,
    ClientFailure? lastFailure,
    required bool removing,
    required bool removalAmbiguous,
    required bool scanning,
    JobRunId? admittedScanJobRunId,
    required bool removalBlockedByActiveScan,
  }) = SourcesRootDetailStateReady;

  /// The syntactically valid root is no longer configured.
  const factory SourcesRootDetailState.missing() =
      SourcesRootDetailStateMissing;
}

/// One application-lifetime owner of authoritative root-detail state.
@Riverpod(keepAlive: true)
class SourcesRootDetailController extends _$SourcesRootDetailController {
  static const String _rootNotFoundCode =
      'ARGUS.V1.CONFIGURATION.LIBRARY_ROOT_NOT_FOUND';

  SourcesRuntimeContext? _lastRuntimeContext;
  AsyncValue<SourcesRootDetailState>? _lastBuildValue;
  LibraryRoot? _lastLoaded;
  RuntimeInstanceId? _activeRuntimeInstanceId;
  int _readToken = 0;
  bool _readInFlight = false;
  bool _scanInFlight = false;
  int _demandToken = 0;
  StreamSubscription<SourcesReconciliationDemand>? _demandSubscription;

  @override
  AsyncValue<SourcesRootDetailState> build(LibraryRootId rootId) {
    ref.onDispose(() {
      _demandToken++;
      _demandSubscription?.cancel();
    });
    final demandSource = ref.watch(sourcesReconciliationDemandProvider);
    _subscribeToDemandSource(demandSource, rootId);
    final context = ref.watch(sourcesRuntimeContextProvider);
    if (context == _lastRuntimeContext && _lastLoaded != null) {
      return _lastBuildValue ?? const AsyncLoading();
    }
    _lastRuntimeContext = context;
    _readToken++;
    _readInFlight = false;
    _activeRuntimeInstanceId = switch (context) {
      SourcesRuntimeContextPreReady() => null,
      SourcesRuntimeContextReady(:final runtimeInstanceId) => runtimeInstanceId,
    };
    scheduleMicrotask(() => unawaited(_readAuthoritative(rootId)));
    return const AsyncLoading();
  }

  /// Issues one focused authoritative root-detail read.
  Future<void> refresh(LibraryRootId rootId) => _readAuthoritative(rootId);

  /// Removes the configured root after presentation-level confirmation.
  ///
  /// A transport-ambiguous removal is never blindly repeated: the controller
  /// reconciles through an authoritative read before the user may retry.
  Future<void> remove(LibraryRootId rootId) async {
    final current = state.value;
    if (current is! SourcesRootDetailStateReady ||
        current.removing ||
        // A transport-ambiguous removal is never repeated: the destructive
        // repeat stays rejected until an authoritative read resolves it.
        current.removalAmbiguous ||
        _readInFlight) {
      return;
    }
    _publish(
      SourcesRootDetailState.ready(
        root: current.root,
        refreshing: current.refreshing,
        lastFailure: current.lastFailure,
        removing: true,
        removalAmbiguous: false,
        scanning: current.scanning,
        admittedScanJobRunId: current.admittedScanJobRunId,
        removalBlockedByActiveScan: false,
      ),
    );
    try {
      final result = await ref
          .read(sourcesApiProvider)
          .removeLibraryRoot(rootId);
      if (result is! RemoveLibraryRootResultRemoved) {
        final blocked = result;
        final latest = state.value;
        if (latest is! SourcesRootDetailStateReady || _readInFlight) return;
        _publish(
          SourcesRootDetailState.ready(
            root: latest.root,
            refreshing: false,
            lastFailure: null,
            removing: false,
            removalAmbiguous: false,
            scanning: false,
            admittedScanJobRunId: latest.admittedScanJobRunId,
            removalBlockedByActiveScan:
                blocked is RemoveLibraryRootResultRootHasActiveScan,
          ),
        );
        return;
      }
      _publish(SourcesRootDetailState.missing());
    } on ClientFailure catch (failure) {
      final latest = state.value;
      if (latest is! SourcesRootDetailStateReady) return;
      final ambiguous = failure is TransportFailure;
      _publish(
        SourcesRootDetailState.ready(
          root: latest.root,
          refreshing: false,
          lastFailure: failure,
          removing: false,
          removalAmbiguous: ambiguous,
          scanning: latest.scanning,
          admittedScanJobRunId: latest.admittedScanJobRunId,
          removalBlockedByActiveScan: latest.removalBlockedByActiveScan,
        ),
      );
      if (ambiguous) {
        // Reconcile authoritative ownership; never repeat the removal.
        await _readAuthoritative(rootId);
      }
    }
  }

  Future<void> _readAuthoritative(LibraryRootId rootId) async {
    final runtimeId = _activeRuntimeInstanceId;
    if (runtimeId == null || _readInFlight) return;
    _readInFlight = true;
    final token = ++_readToken;
    final api = ref.read(sourcesApiProvider);
    try {
      final root = await api.getLibraryRoot(rootId);
      if (token != _readToken || runtimeId != _activeRuntimeInstanceId) return;
      final current = state.value;
      final removing =
          current is SourcesRootDetailStateReady && current.removing;
      _lastLoaded = root;
      _publish(
        SourcesRootDetailState.ready(
          root: root,
          refreshing: false,
          removing: removing,
          scanning: current is SourcesRootDetailStateReady && current.scanning,
          admittedScanJobRunId: current is SourcesRootDetailStateReady
              ? current.admittedScanJobRunId
              : null,
          removalBlockedByActiveScan:
              current is SourcesRootDetailStateReady &&
              current.removalBlockedByActiveScan,
          // A successful authoritative read proves the current root exists,
          // which resolves any prior transport-ambiguous removal uncertainty.
          removalAmbiguous: false,
          lastFailure: null,
        ),
      );
    } on ClientFailure catch (failure) {
      if (token != _readToken || runtimeId != _activeRuntimeInstanceId) return;
      if (_isRootNotFound(failure)) {
        _lastLoaded = null;
        _publish(const SourcesRootDetailState.missing());
        return;
      }
      final current = state.value;
      if (current is! SourcesRootDetailStateReady) {
        _setState(AsyncError(failure, StackTrace.current));
        return;
      }
      _publish(
        SourcesRootDetailState.ready(
          root: current.root,
          refreshing: false,
          lastFailure: failure,
          removing: current.removing,
          scanning: current.scanning,
          admittedScanJobRunId: current.admittedScanJobRunId,
          removalBlockedByActiveScan: current.removalBlockedByActiveScan,
          removalAmbiguous: current.removalAmbiguous,
        ),
      );
    } finally {
      if (token == _readToken) {
        _readInFlight = false;
      }
    }
  }

  void _subscribeToDemandSource(
    SourcesReconciliationDemandSource source,
    LibraryRootId rootId,
  ) {
    _demandToken++;
    final token = _demandToken;
    final subscription = source.stream.listen((demand) {
      if (token != _demandToken) return;
      switch (demand) {
        case SourcesReconciliationDemandRootsChanged():
          unawaited(_readAuthoritative(rootId));
        case SourcesReconciliationDemandRootChanged(:final libraryRootId):
          if (libraryRootId == rootId) {
            unawaited(_readAuthoritative(rootId));
          }
        case SourcesReconciliationDemandSourceChanged():
          // Source scopes are owned by the hierarchy controller.
          break;
      }
    });
    final previous = _demandSubscription;
    _demandSubscription = subscription;
    previous?.cancel();
  }

  bool _isRootNotFound(ClientFailure failure) =>
      failure is ApplicationFailure &&
      failure.error.code.value == _rootNotFoundCode;

  /// Starts one single-root scan when the root is eligible. Returns the
  /// authoritative job identity on admission or an already-active owner.
  Future<JobRunId?> startScan(LibraryRootId rootId) async {
    final current = state.value;
    if (current is! SourcesRootDetailStateReady ||
        current.scanning ||
        _scanInFlight ||
        current.root.activeScan != null ||
        current.root.lastScan != null) {
      return null;
    }
    _scanInFlight = true;
    _publish(
      SourcesRootDetailState.ready(
        root: current.root,
        refreshing: false,
        lastFailure: null,
        removing: false,
        removalAmbiguous: false,
        scanning: true,
        removalBlockedByActiveScan: false,
      ),
    );
    try {
      final result = await ref
          .read(sourcesApiProvider)
          .startLibraryScan(rootId);
      switch (result) {
        case StartLibraryScanResultAdmitted(:final handle):
          final latest = state.value;
          if (latest is! SourcesRootDetailStateReady) return null;
          _publish(
            SourcesRootDetailState.ready(
              root: latest.root,
              refreshing: false,
              lastFailure: null,
              removing: false,
              removalAmbiguous: false,
              scanning: false,
              admittedScanJobRunId: handle.jobRunId,
              removalBlockedByActiveScan: false,
            ),
          );
          await _readAuthoritative(rootId);
          return handle.jobRunId;
        case StartLibraryScanResultAlreadyScanning(:final activeJobRunId):
          await _readAuthoritative(rootId);
          return activeJobRunId;
      }
    } on ClientFailure catch (failure) {
      final latest = state.value;
      if (latest is! SourcesRootDetailStateReady) return null;
      _publish(
        SourcesRootDetailState.ready(
          root: latest.root,
          refreshing: false,
          lastFailure: failure,
          removing: false,
          removalAmbiguous: false,
          scanning: false,
          admittedScanJobRunId: null,
          removalBlockedByActiveScan: false,
        ),
      );
      return null;
    } finally {
      _scanInFlight = false;
    }
  }

  void _publish(SourcesRootDetailState next) {
    _setState(AsyncData(next));
  }

  void _setState(AsyncValue<SourcesRootDetailState> next) {
    _lastBuildValue = next;
    state = next;
  }
}
