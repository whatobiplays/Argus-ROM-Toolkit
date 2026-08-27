// The constructor keeps public parameter names while assigning private fields.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:argus/features/library/library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Interprets runtime event envelopes for the Library feature.
///
/// The coordinator owns sequence continuity and runtime-generation checks.
/// It emits only invalidation hints; Library controllers always re-read their
/// complete authoritative query shape after receiving one.
final class LibraryEventCoordinator {
  LibraryEventCoordinator({
    required EventsApi events,
    required RuntimeInstanceId? runtimeInstanceId,
  }) : _runtimeInstanceId = runtimeInstanceId {
    _subscription = events.events.listen(
      _onEvent,
      onError: (Object _, StackTrace _) {
        if (_runtimeInstanceId != null) _emitListChanged();
      },
      onDone: () {
        if (_runtimeInstanceId != null) _emitListChanged();
      },
      cancelOnError: false,
    );
  }

  final RuntimeInstanceId? _runtimeInstanceId;
  final StreamController<LibraryReconciliationDemand> _demands =
      StreamController<LibraryReconciliationDemand>.broadcast();
  late final StreamSubscription<RuntimeEvent> _subscription;
  BigInt? _lastSequence;
  bool _disposed = false;

  LibraryReconciliationDemandSource get source =>
      LibraryReconciliationDemandSource(_demands.stream);

  void _onEvent(RuntimeEvent event) {
    if (_disposed || _runtimeInstanceId == null) return;
    if (event.runtimeInstanceId != _runtimeInstanceId) return;

    final previous = _lastSequence;
    if (previous != null && event.sequence != previous + BigInt.one) {
      _emitListChanged();
      if (event.sequence > previous) _lastSequence = event.sequence;
      return;
    }
    if (previous == null || event.sequence > previous) {
      _lastSequence = event.sequence;
    }
    if (previous != null && event.sequence <= previous) return;
    _emitForPayload(event.payload);
  }

  void _emitForPayload(RuntimeEventPayload payload) {
    switch (payload) {
      case RuntimeEventPayloadLibraryRootsChanged():
      case RuntimeEventPayloadLibraryRootChanged():
      case RuntimeEventPayloadSourceEntriesChanged():
      case RuntimeEventPayloadJobStateChanged():
        _emitListChanged();
      default:
        break;
    }
  }

  void _emitListChanged() {
    if (!_disposed && !_demands.isClosed) {
      _demands.add(const LibraryReconciliationDemand.listChanged());
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_subscription.cancel());
    unawaited(_demands.close());
  }
}

/// App-level Riverpod composition for the Library event channel.
final libraryEventCoordinatorProvider =
    Provider<LibraryReconciliationDemandSource>((ref) {
      final coordinator = LibraryEventCoordinator(
        events: ref.watch(runtimeEventsProvider),
        runtimeInstanceId: ref.watch(readyRuntimeInstanceIdProvider),
      );
      ref.onDispose(coordinator.dispose);
      return coordinator.source;
    });
