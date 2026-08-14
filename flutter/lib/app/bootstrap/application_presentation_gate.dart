import 'package:argus/core/client/client.dart';
import 'package:argus/features/settings/settings_composition.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application_presentation.dart';

/// Nested appearance admission gate inside the backend [StartupGate].
///
/// Backend `Ready` is necessary but not sufficient for first-shell
/// presentation: the routed child appears only after the first authoritative
/// appearance snapshot exists.
class ApplicationPresentationGate extends ConsumerWidget {
  /// Creates the gate around the router-provided navigator child.
  const ApplicationPresentationGate({required this.child, super.key});

  /// The routed shell exposed once appearance authority is established.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readiness = ref.watch(applicationPresentationReadinessProvider);
    return switch (readiness) {
      ApplicationPresentationReadiness.preReady => const SizedBox.shrink(),
      ApplicationPresentationReadiness.appearanceInitializing =>
        const AppearanceInitializationView(),
      ApplicationPresentationReadiness.appearanceUnavailable =>
        AppearanceInitializationFailureView(
          failure:
              ref.watch(appearanceSettingsControllerProvider).error
                  as ClientFailure,
          onRetry: () => ref
              .read(appearanceSettingsControllerProvider.notifier)
              .retryAuthoritativeRead(),
          onExit: () => ref.read(appTerminatorProvider)(),
        ),
      ApplicationPresentationReadiness.ready => child,
    };
  }
}
