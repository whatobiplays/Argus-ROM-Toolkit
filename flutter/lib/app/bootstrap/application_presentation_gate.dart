import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/application/library_onboarding_routing.dart';
import 'package:argus/features/settings/settings_composition.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application_presentation.dart';

/// Nested presentation admission gate inside the backend [StartupGate].
///
/// Backend `Ready` is necessary but not sufficient for first-shell
/// presentation: the routed child appears only after authoritative appearance
/// and Library onboarding snapshots exist, or when the Library capability is
/// explicitly unavailable.
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
      ApplicationPresentationReadiness.onboardingInitializing => const Center(
        child: CircularProgressIndicator(),
      ),
      ApplicationPresentationReadiness.onboardingUnavailable =>
        _OnboardingInitializationFailureView(
          onRetry: () =>
              ref.read(libraryOnboardingRoutingProvider.notifier).retry(),
          onExit: () => ref.read(appTerminatorProvider)(),
        ),
      ApplicationPresentationReadiness.libraryUnavailable ||
      ApplicationPresentationReadiness.onboardingRequired ||
      ApplicationPresentationReadiness.ready => child,
    };
  }
}

/// Bounded recovery surface for an onboarding authority read that failed
/// before routing could admit the application shell.
final class _OnboardingInitializationFailureView extends StatelessWidget {
  const _OnboardingInitializationFailureView({
    required this.onRetry,
    required this.onExit,
  });

  final VoidCallback onRetry;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('Library setup unavailable'),
          const SizedBox(height: 12),
          const Text('Argus could not read the saved Library setup state.'),
          const SizedBox(height: 20),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
          TextButton(onPressed: onExit, child: const Text('Exit')),
        ],
      ),
    ),
  );
}
