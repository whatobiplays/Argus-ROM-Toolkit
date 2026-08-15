import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:argus/features/sources/sources.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_bootstrap.dart';

part 'sources_event_coordinator.g.dart';

/// App-level owner of runtime-event delivery interpretation for Sources.
///
/// This is the only Sources consumer that reads [EventsApi] envelopes and
/// stream continuity. It consumes the shared mapped stream (owned by the root
/// client) and projects each observable delivery condition onto narrow
/// [SourcesReconciliationDemand] signals so the Sources feature can stay
/// transport-agnostic.
@Riverpod(keepAlive: true)
class SourcesEventCoordinator extends _$SourcesEventCoordinator {
  StreamController<SourcesReconciliationDemand>? _demands;
  StreamSubscription<RuntimeEvent>? _eventSubscription;
  int _subscriptionToken = 0;
  RuntimeInstanceId? _domainRuntimeId;
  BigInt? _lastSequence;
  final Set<LibraryRootId> _recentSourceRootIds = {};

  @override
  SourcesReconciliationDemandSource build() {
    final demands = StreamController<SourcesReconciliationDemand>.broadcast();
    _demands = demands;
    ref.onDispose(() {
      _subscriptionToken++;
      _eventSubscription?.cancel();
      demands.close();
    });
    final runtimeId = ref.watch(readyRuntimeInstanceIdProvider);
    final events = ref.watch(runtimeEventsProvider);
    _resetDomain(runtimeId);
    _subscribe(events);
    return SourcesReconciliationDemandSource(demands.stream);
  }

  /// Resets sequence-domain tracking for a (possibly new) ready runtime.
  void _resetDomain(RuntimeInstanceId? runtimeId) {
    _domainRuntimeId = runtimeId;
    _lastSequence = null;
    _recentSourceRootIds.clear();
  }

  /// Subscribes to a mapped [EventsApi] stream without owning reconnect.
  void _subscribe(EventsApi events) {
    _subscriptionToken++;
    _eventSubscription?.cancel();
    final token = _subscriptionToken;
    _eventSubscription = events.events.listen(
      (event) {
        if (token == _subscriptionToken) _onEvent(event);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (token == _subscriptionToken && _domainRuntimeId != null) {
          _emitRootsChangedDemand();
          _emitBroadSourceDemands();
        }
      },
      onDone: () {
        if (token == _subscriptionToken && _domainRuntimeId != null) {
          _emitRootsChangedDemand();
          _emitBroadSourceDemands();
        }
      },
      cancelOnError: false,
    );
  }

  void _onEvent(RuntimeEvent event) {
    final runtimeId = _domainRuntimeId;
    if (runtimeId == null || event.runtimeInstanceId != runtimeId) return;

    final previous = _lastSequence;
    final relevantPayload = event.payload;

    if (previous == null) {
      _lastSequence = event.sequence;
      _emitForPayload(relevantPayload);
      return;
    }

    if (event.sequence == previous + BigInt.one) {
      _lastSequence = event.sequence;
      _emitForPayload(relevantPayload);
      return;
    }

    // Any non-contiguous same-runtime sequence is delivery uncertainty and
    // requires one authoritative root-list refresh plus a broad loaded-hierarchy
    // refresh for every root that had source-graph activity, regardless of
    // payload. Events are never replayed.
    _emitRootsChangedDemand();
    _emitBroadSourceDemands();
    if (event.sequence > previous) {
      _lastSequence = event.sequence;
    }
  }

  void _emitForPayload(RuntimeEventPayload payload) {
    switch (payload) {
      case RuntimeEventPayloadLibraryRootsChanged():
        _emitRootsChangedDemand();
      case RuntimeEventPayloadLibraryRootChanged(:final libraryRootId):
        _emitRootChangedDemand(libraryRootId);
      case RuntimeEventPayloadSourceEntriesChanged(
        :final libraryRootId,
        :final scope,
      ):
        _recentSourceRootIds.add(libraryRootId);
        _emitSourceChangedDemand(libraryRootId, scope);
      default:
        // Other payload families do not invalidate Sources state.
        break;
    }
  }

  void _emitBroadSourceDemands() {
    for (final libraryRootId in _recentSourceRootIds.toList()) {
      _emitSourceChangedDemand(
        libraryRootId,
        const SourceEntriesChangeScope.entireRootHierarchy(),
      );
    }
  }

  void _emitSourceChangedDemand(
    LibraryRootId libraryRootId,
    SourceEntriesChangeScope scope,
  ) {
    final demands = _demands;
    if (demands != null && !demands.isClosed) {
      demands.add(
        SourcesReconciliationDemand.sourceChanged(
          libraryRootId: libraryRootId,
          scope: scope,
        ),
      );
    }
  }

  void _emitRootsChangedDemand() {
    final demands = _demands;
    if (demands != null && !demands.isClosed) {
      demands.add(const SourcesReconciliationDemand.rootsChanged());
    }
  }

  void _emitRootChangedDemand(LibraryRootId libraryRootId) {
    final demands = _demands;
    if (demands != null && !demands.isClosed) {
      demands.add(
        SourcesReconciliationDemand.rootChanged(libraryRootId: libraryRootId),
      );
    }
  }
}
