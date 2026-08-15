import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../jobs_composition.dart';
import 'jobs_state.dart';

part 'active_job_summary_controller.g.dart';

/// Narrow app/shell-safe active-job summary.
///
/// This provider is the only shell dependency: it never depends on Jobs list
/// or detail controllers, Sources state, or locally initiated mutations.
@Riverpod(keepAlive: true)
class ActiveJobSummaryController extends _$ActiveJobSummaryController {
  JobsRuntimeContext? _lastRuntimeContext;
  ActiveJobSummary? _lastLoaded;
  RuntimeInstanceId? _activeRuntimeInstanceId;
  int _loadToken = 0;
  bool _loadInFlight = false;
  int _demandToken = 0;
  StreamSubscription<JobsReconciliationDemand>? _demandSubscription;

  @override
  AsyncValue<ActiveJobSummary> build() {
    ref.onDispose(() {
      _demandToken++;
      _demandSubscription?.cancel();
    });
    final demandSource = ref.watch(jobsReconciliationDemandProvider);
    _subscribeToDemandSource(demandSource);
    final context = ref.watch(jobsRuntimeContextProvider);
    if (context == _lastRuntimeContext && _lastLoaded != null) {
      return AsyncData(_lastLoaded!);
    }
    _lastRuntimeContext = context;
    _loadToken++;
    _loadInFlight = false;
    _activeRuntimeInstanceId = switch (context) {
      JobsRuntimeContextPreReady() => null,
      JobsRuntimeContextReady(:final runtimeInstanceId) => runtimeInstanceId,
    };
    scheduleMicrotask(() => unawaited(_loadAuthoritative()));
    return AsyncData(_lastLoaded ?? const ActiveJobSummary(activeCount: 0));
  }

  Future<void> refresh() => _loadAuthoritative();

  Future<void> _loadAuthoritative() async {
    final runtimeId = _activeRuntimeInstanceId;
    if (runtimeId == null || _loadInFlight) return;
    _loadInFlight = true;
    final token = ++_loadToken;
    try {
      final summary = await ref.read(jobsApiProvider).getActiveJobSummary();
      if (token != _loadToken || runtimeId != _activeRuntimeInstanceId) return;
      _lastLoaded = summary;
      state = AsyncData(summary);
    } on ClientFailure {
      // The shell indicator stays hidden/unchanged on failure; Jobs remains
      // reachable and reconciles through its own authoritative reads.
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
      unawaited(refresh());
    });
    final previous = _demandSubscription;
    _demandSubscription = subscription;
    previous?.cancel();
  }
}
