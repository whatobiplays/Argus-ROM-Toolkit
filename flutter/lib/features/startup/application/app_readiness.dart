import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'startup_controller.dart';
import 'startup_state.dart';

part 'app_readiness.g.dart';

/// Narrow backend-readiness projection consumed by app composition.
///
/// This is the FE-005 backend admission gate only; Slice 007 adds initial
/// appearance authority before first-shell presentation.
enum AppReadiness { preReady, startupFailed, ready }

/// Projects authoritative startup state onto the narrow admission policy.
@Riverpod(keepAlive: true)
AppReadiness appReadiness(Ref ref) {
  final value = ref.watch(startupControllerProvider).value;
  return switch (value) {
    StartupStateReady() => AppReadiness.ready,
    StartupStateStartupFailed() => AppReadiness.startupFailed,
    _ => AppReadiness.preReady,
  };
}

/// Convenience projection used by composition boundaries that only need to
/// distinguish a certified failed runtime from other pre-ready states.
bool appReadinessIsPreShell(AppReadiness readiness) =>
    readiness != AppReadiness.ready;
