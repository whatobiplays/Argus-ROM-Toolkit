import 'dart:async';

import 'package:argus/app/platform/application/platform_readiness_controller.dart';
import 'package:argus/app/platform/application/platform_readiness_state.dart';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'application_lifecycle_coordinator.g.dart';

/// One coalesced, read-only request for app-owned feature reconciliation.
final class ApplicationLifecycleReconciliationDemand {
  const ApplicationLifecycleReconciliationDemand();
}

/// Synchronous carrier for the app-lifecycle reconciliation stream.
final class ApplicationLifecycleReconciliationDemandSource {
  const ApplicationLifecycleReconciliationDemandSource(this.stream);

  final Stream<ApplicationLifecycleReconciliationDemand> stream;
}

/// Sole app-lifetime observer for lifecycle transitions.
///
/// The coordinator certifies Android readiness after a resume, then publishes
/// one bounded demand for app composition to map onto existing feature seams.
/// It deliberately does not retain or register feature controllers.
@Riverpod(keepAlive: true)
class ApplicationLifecycleCoordinator extends _$ApplicationLifecycleCoordinator
    with WidgetsBindingObserver {
  StreamController<ApplicationLifecycleReconciliationDemand>? _demands;
  bool _resumeQueued = false;
  bool _resuming = false;

  @override
  ApplicationLifecycleReconciliationDemandSource build() {
    final demands =
        StreamController<ApplicationLifecycleReconciliationDemand>.broadcast();
    _demands = demands;
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      unawaited(demands.close());
    });
    return ApplicationLifecycleReconciliationDemandSource(demands.stream);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _resumeQueued || _resuming) {
      return;
    }
    _resumeQueued = true;
    scheduleMicrotask(_reconcileAfterResume);
  }

  Future<void> _reconcileAfterResume() async {
    _resumeQueued = false;
    if (!ref.mounted) return;
    _resuming = true;
    try {
      if (ref.read(platformReadinessRequiredProvider)) {
        await ref.read(platformReadinessControllerProvider.notifier).refresh();
        if (!ref.mounted) return;
        if (ref.read(platformReadinessControllerProvider)
            is! PlatformReadinessReady) {
          return;
        }
      }
      if (!ref.mounted) return;
      final demands = _demands;
      if (demands != null && !demands.isClosed) {
        demands.add(const ApplicationLifecycleReconciliationDemand());
      }
    } finally {
      _resuming = false;
    }
  }
}

/// Exposes the coordinator's read-only signal to app composition.
@Riverpod(keepAlive: true)
ApplicationLifecycleReconciliationDemandSource
applicationLifecycleReconciliationDemand(Ref ref) =>
    ref.watch(applicationLifecycleCoordinatorProvider);
