import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:argus/features/settings/settings_composition.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_bootstrap.dart';

part 'appearance_event_coordinator.g.dart';

/// App-level owner of runtime-event delivery interpretation for appearance.
///
/// This is the only appearance consumer that reads [EventsApi] envelopes and
/// stream continuity. It consumes the shared mapped stream (owned by the root
/// client) and projects each observable delivery condition onto exactly one
/// narrow [AppearanceReconciliationDemand] so the Settings feature can stay
/// transport-agnostic.
@Riverpod(keepAlive: true)
class AppearanceEventCoordinator extends _$AppearanceEventCoordinator {
  StreamController<AppearanceReconciliationDemand>? _demands;
  StreamSubscription<RuntimeEvent>? _eventSubscription;
  int _subscriptionToken = 0;
  RuntimeInstanceId? _domainRuntimeId;
  BigInt? _lastSequence;

  @override
  AppearanceReconciliationDemandSource build() {
    // The demand channel is scoped to this build: Riverpod invokes onDispose
    // whenever this keep-alive notifier rebuilds, so every build owns a fresh
    // controller and subscription generation.
    final demands =
        StreamController<AppearanceReconciliationDemand>.broadcast();
    _demands = demands;
    ref.onDispose(() {
      _subscriptionToken++;
      _eventSubscription?.cancel();
      demands.close();
    });
    // Watching both inputs rebuilds this coordinator whenever the ready
    // runtime generation or the mapped EventsApi projection is replaced,
    // resetting the sequence domain without leaking old-generation signals.
    final runtimeId = ref.watch(readyRuntimeInstanceIdProvider);
    final events = ref.watch(runtimeEventsProvider);
    _resetDomain(runtimeId);
    _subscribe(events);
    return AppearanceReconciliationDemandSource(demands.stream);
  }

  /// Resets sequence-domain tracking for a (possibly new) ready runtime.
  ///
  /// The first accepted event of the new domain establishes its baseline.
  void _resetDomain(RuntimeInstanceId? runtimeId) {
    _domainRuntimeId = runtimeId;
    _lastSequence = null;
  }

  /// Subscribes to a mapped [EventsApi] stream without owning reconnect.
  ///
  /// The root client owns the single native event connection and any
  /// reconnection; this coordinator only interprets what the mapped stream
  /// delivers. Stale subscription callbacks are suppressed with a token so a
  /// replaced stream can never publish into the new domain.
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
          _emitDemand();
        }
      },
      onDone: () {
        if (token == _subscriptionToken && _domainRuntimeId != null) {
          _emitDemand();
        }
      },
      cancelOnError: false,
    );
  }

  void _onEvent(RuntimeEvent event) {
    final runtimeId = _domainRuntimeId;
    if (runtimeId == null || event.runtimeInstanceId != runtimeId) return;

    final previous = _lastSequence;
    final relevant =
        event.payload is RuntimeEventPayloadAppearanceSettingsChanged;

    if (previous == null) {
      // First accepted current-generation event establishes the baseline.
      _lastSequence = event.sequence;
      if (relevant) _emitDemand();
      return;
    }

    if (event.sequence == previous + BigInt.one) {
      _lastSequence = event.sequence;
      if (relevant) _emitDemand();
      return;
    }

    // Any non-contiguous same-runtime sequence is delivery uncertainty and
    // requires one authoritative refresh, regardless of the observed payload.
    _emitDemand();
    if (event.sequence > previous) {
      // Forward gaps advance the baseline; duplicates/regressions do not
      // rewind an already-established baseline.
      _lastSequence = event.sequence;
    }
  }

  void _emitDemand() {
    final demands = _demands;
    if (demands != null && !demands.isClosed) {
      demands.add(const AppearanceReconciliationDemandRefresh());
    }
  }
}
