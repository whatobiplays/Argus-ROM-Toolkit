import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:argus/features/jobs/jobs.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_bootstrap.dart';

part 'jobs_event_coordinator.g.dart';

/// App-level owner of runtime-event delivery interpretation for Jobs.
///
/// This is the only Jobs consumer that reads [EventsApi] envelopes and stream
/// continuity. Job notifications only trigger authoritative reconciliation;
/// they never mutate lifecycle state locally.
@Riverpod(keepAlive: true)
class JobsEventCoordinator extends _$JobsEventCoordinator {
  StreamController<JobsReconciliationDemand>? _demands;
  StreamSubscription<RuntimeEvent>? _eventSubscription;
  int _subscriptionToken = 0;
  RuntimeInstanceId? _domainRuntimeId;
  BigInt? _lastSequence;

  @override
  JobsReconciliationDemandSource build() {
    final demands = StreamController<JobsReconciliationDemand>.broadcast();
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
    return JobsReconciliationDemandSource(demands.stream);
  }

  void _resetDomain(RuntimeInstanceId? runtimeId) {
    _domainRuntimeId = runtimeId;
    _lastSequence = null;
  }

  void _subscribe(EventsApi events) {
    _subscriptionToken++;
    _eventSubscription?.cancel();
    final token = _subscriptionToken;
    _eventSubscription = events.events.listen(
      (event) {
        if (token == _subscriptionToken) _onEvent(event);
      },
      onError: (Object _, StackTrace _) {
        if (token == _subscriptionToken && _domainRuntimeId != null) {
          _emitListChangedDemand();
        }
      },
      onDone: () {
        if (token == _subscriptionToken && _domainRuntimeId != null) {
          _emitListChangedDemand();
        }
      },
      cancelOnError: false,
    );
  }

  void _onEvent(RuntimeEvent event) {
    final runtimeId = _domainRuntimeId;
    if (runtimeId == null || event.runtimeInstanceId != runtimeId) return;

    final previous = _lastSequence;
    if (previous == null) {
      _lastSequence = event.sequence;
      _emitForPayload(event.payload);
      return;
    }
    if (event.sequence == previous + BigInt.one) {
      _lastSequence = event.sequence;
      _emitForPayload(event.payload);
      return;
    }
    _emitListChangedDemand();
    if (event.sequence > previous) {
      _lastSequence = event.sequence;
    }
  }

  void _emitForPayload(RuntimeEventPayload payload) {
    switch (payload) {
      case RuntimeEventPayloadJobStateChanged(:final jobRunId):
        _emitDetailChangedDemand(jobRunId);
        _emitListChangedDemand();
      case RuntimeEventPayloadJobProgress(:final jobRunId):
        _emitDetailChangedDemand(jobRunId);
      default:
        break;
    }
  }

  void _emitListChangedDemand() {
    final demands = _demands;
    if (demands != null && !demands.isClosed) {
      demands.add(const JobsReconciliationDemand.listChanged());
    }
  }

  void _emitDetailChangedDemand(JobRunId jobRunId) {
    final demands = _demands;
    if (demands != null && !demands.isClosed) {
      demands.add(JobsReconciliationDemand.detailChanged(jobRunId: jobRunId));
    }
  }
}
