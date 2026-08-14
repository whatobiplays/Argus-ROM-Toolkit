import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/app_readiness.dart';
import '../application/startup_controller.dart';
import '../application/startup_state.dart';
import 'presentation_seams.dart';
import 'startup_loading_view.dart';
import 'startup_failure_view.dart';
import 'bootstrap_failure_view.dart';
import 'runtime_unavailable_view.dart';
import 'shutdown_views.dart';

/// Root admission boundary between the pre-ready startup/recovery surfaces
/// and the routed application shell.
///
/// Presentation is selected from the full [StartupState], but the routed
/// child is exposed only through the narrow [AppReadiness] projection.
class StartupGate extends ConsumerStatefulWidget {
  /// Creates the gate around the router-provided navigator child.
  const StartupGate({required this.child, super.key});

  /// The router navigator exposed once backend readiness is certified.
  final Widget child;

  @override
  ConsumerState<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends ConsumerState<StartupGate> {
  bool _terminationRequested = false;

  @override
  Widget build(BuildContext context) {
    final readiness = ref.watch(appReadinessProvider);
    if (readiness == AppReadiness.ready) {
      return widget.child;
    }

    ref.listen<AsyncValue<StartupState>>(startupControllerProvider, (
      previous,
      next,
    ) {
      if (!_terminationRequested && next.value is StartupStateStopped) {
        _terminationRequested = true;
        ref.read(appTerminatorProvider)();
      }
    });

    return ref
        .watch(startupControllerProvider)
        .when(
          data: (value) => _dataSurface(ref, value),
          error: (error, stackTrace) => BootstrapFailureView(failure: error),
          loading: () => const StartupLoadingView(),
        );
  }

  Widget _dataSurface(WidgetRef ref, StartupState value) => switch (value) {
    StartupStateUninitialized() ||
    StartupStateStarting() => const StartupLoadingView(),
    StartupStateStartupFailed() => StartupFailureView(state: value),
    StartupStateRuntimeUnavailable() => RuntimeUnavailableView(state: value),
    StartupStateShuttingDown() => const ShuttingDownView(),
    StartupStateStopped() => const StoppedView(),
    StartupStateReady() => widget.child,
  };
}
