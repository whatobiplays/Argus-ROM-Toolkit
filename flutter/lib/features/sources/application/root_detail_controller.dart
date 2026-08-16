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
    LibraryRootActiveScan? removalBlockedOwner,
    required bool cancelAndRemovePending,
    required bool cancelAndRemoveAmbiguous,
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
  bool _cancelRemoveInFlight = false;
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

  /// Removes the configured root after plain confirmation.
  ///
  /// A transport-ambiguous removal is never blindly repeated: the controller
  /// reconciles through an authoritative read before the user may retry. A
  /// `RootHasActiveScan` race result enters the same guided cancel-and-remove
  /// workflow surfaced through [removalBlockedOwner].
  Future<void> remove(LibraryRootId rootId) async {
    final current = state.value;
    if (current is! SourcesRootDetailStateReady ||
        current.removing ||
        current.cancelAndRemovePending ||
        current.cancelAndRemoveAmbiguous ||
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
        removalBlockedOwner: null,
        cancelAndRemovePending: false,
        cancelAndRemoveAmbiguous: false,
      ),
    );
    try {
      final result = await ref
          .read(sourcesApiProvider)
          .removeLibraryRoot(rootId);
      _applyRemovalResult(result);
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
          removalBlockedOwner: latest.removalBlockedOwner,
          cancelAndRemovePending: false,
          cancelAndRemoveAmbiguous: false,
        ),
      );
      if (ambiguous) {
        // Reconcile authoritative ownership; never repeat the removal.
        await _readAuthoritative(rootId);
      }
    }
  }

  /// Executes the guided Cancel Scan & Remove sequence:
  /// cancelJob -> authoritative job/root reconciliation -> prove no active
  /// owner -> removeLibraryRoot. Definite or transport-ambiguous cancellation
  /// failure never proceeds destructively; only an authoritative read proving
  /// ownership ended allows removal to continue.
  Future<void> cancelAndRemove(LibraryRootId rootId, JobRunId jobRunId) async {
    final current = state.value;
    if (current is! SourcesRootDetailStateReady ||
        current.removing ||
        current.cancelAndRemovePending ||
        current.cancelAndRemoveAmbiguous ||
        current.removalAmbiguous ||
        _readInFlight ||
        _cancelRemoveInFlight) {
      return;
    }
    _cancelRemoveInFlight = true;
    _publish(
      SourcesRootDetailState.ready(
        root: current.root,
        refreshing: false,
        lastFailure: null,
        removing: false,
        removalAmbiguous: false,
        scanning: current.scanning,
        admittedScanJobRunId: current.admittedScanJobRunId,
        removalBlockedByActiveScan: false,
        removalBlockedOwner: null,
        cancelAndRemovePending: true,
        cancelAndRemoveAmbiguous: false,
      ),
    );
    try {
      final cancel = await ref.read(sourcesJobsApiProvider).cancelJob(jobRunId);
      if (cancel == CancelJobResult.noLongerCancellable) {
        // The job is already terminal; authoritative reconciliation decides
        // whether the root still has an active owner.
      }
      await _removeAfterOwnershipProven(rootId);
    } on ClientFailure catch (failure) {
      final latest = state.value;
      if (latest is! SourcesRootDetailStateReady) return;
      if (failure is TransportFailure) {
        _publish(
          SourcesRootDetailState.ready(
            root: latest.root,
            refreshing: false,
            lastFailure: failure,
            removing: false,
            removalAmbiguous: false,
            scanning: latest.scanning,
            admittedScanJobRunId: latest.admittedScanJobRunId,
            removalBlockedByActiveScan: false,
            removalBlockedOwner: null,
            cancelAndRemovePending: false,
            cancelAndRemoveAmbiguous: true,
          ),
        );
        // Never repeat the cancel destructively. Reconcile authority; only a
        // proven absence of ownership may continue to removal.
        await _readAuthoritative(rootId);
        final reconciled = state.value;
        if (reconciled is SourcesRootDetailStateReady &&
            reconciled.root.activeScan == null) {
          await _removeAfterOwnershipProven(rootId);
        }
        return;
      }
      _publish(
        SourcesRootDetailState.ready(
          root: latest.root,
          refreshing: false,
          lastFailure: failure,
          removing: false,
          removalAmbiguous: false,
          scanning: latest.scanning,
          admittedScanJobRunId: latest.admittedScanJobRunId,
          removalBlockedByActiveScan: false,
          removalBlockedOwner: null,
          cancelAndRemovePending: false,
          cancelAndRemoveAmbiguous: false,
        ),
      );
    } finally {
      _cancelRemoveInFlight = false;
    }
  }

  Future<void> _removeAfterOwnershipProven(LibraryRootId rootId) async {
    await _readAuthoritative(rootId);
    final current = state.value;
    if (current is! SourcesRootDetailStateReady) return;
    final owner = current.root.activeScan;
    if (owner != null) {
      _publish(
        SourcesRootDetailState.ready(
          root: current.root,
          refreshing: false,
          lastFailure: null,
          removing: false,
          removalAmbiguous: false,
          scanning: current.scanning,
          admittedScanJobRunId: current.admittedScanJobRunId,
          removalBlockedByActiveScan: true,
          removalBlockedOwner: owner,
          cancelAndRemovePending: false,
          cancelAndRemoveAmbiguous: false,
        ),
      );
      return;
    }
    try {
      final result = await ref
          .read(sourcesApiProvider)
          .removeLibraryRoot(rootId);
      _applyRemovalResult(result);
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
          removalBlockedOwner: latest.removalBlockedOwner,
          cancelAndRemovePending: false,
          cancelAndRemoveAmbiguous: false,
        ),
      );
      if (ambiguous) {
        await _readAuthoritative(rootId);
      }
    }
  }

  void _applyRemovalResult(RemoveLibraryRootResult result) {
    switch (result) {
      case RemoveLibraryRootResultRemoved():
        _publish(const SourcesRootDetailState.missing());
      case RemoveLibraryRootResultRootHasActiveScan(
        :final jobRunId,
        :final scanRunId,
        :final owningJobRootCount,
      ):
        final latest = state.value;
        if (latest is! SourcesRootDetailStateReady) return;
        _publish(
          SourcesRootDetailState.ready(
            root: latest.root,
            refreshing: false,
            lastFailure: null,
            removing: false,
            removalAmbiguous: false,
            scanning: false,
            admittedScanJobRunId: latest.admittedScanJobRunId,
            removalBlockedByActiveScan: true,
            removalBlockedOwner: LibraryRootActiveScan(
              scanRunId: scanRunId.value,
              jobRunId: jobRunId.value,
              owningJobRootCount: owningJobRootCount,
            ),
            cancelAndRemovePending: false,
            cancelAndRemoveAmbiguous: false,
          ),
        );
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
      if (!ref.mounted ||
          token != _readToken ||
          runtimeId != _activeRuntimeInstanceId) {
        return;
      }
      final current = state.value;
      final removing =
          current is SourcesRootDetailStateReady && current.removing;
      final cancelAndRemovePending =
          current is SourcesRootDetailStateReady &&
          current.cancelAndRemovePending;
      final cancelAndRemoveAmbiguous =
          current is SourcesRootDetailStateReady &&
          current.cancelAndRemoveAmbiguous;
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
          removalBlockedOwner: current is SourcesRootDetailStateReady
              ? current.removalBlockedOwner
              : null,
          cancelAndRemovePending: cancelAndRemovePending,
          cancelAndRemoveAmbiguous: cancelAndRemoveAmbiguous,
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
          removalBlockedOwner: current.removalBlockedOwner,
          cancelAndRemovePending: current.cancelAndRemovePending,
          cancelAndRemoveAmbiguous: current.cancelAndRemoveAmbiguous,
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
        current.root.activeScan != null) {
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
        admittedScanJobRunId: null,
        removalBlockedByActiveScan: false,
        removalBlockedOwner: null,
        cancelAndRemovePending: false,
        cancelAndRemoveAmbiguous: false,
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
              removalBlockedOwner: null,
              cancelAndRemovePending: false,
              cancelAndRemoveAmbiguous: false,
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
          removalBlockedOwner: null,
          cancelAndRemovePending: false,
          cancelAndRemoveAmbiguous: false,
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
