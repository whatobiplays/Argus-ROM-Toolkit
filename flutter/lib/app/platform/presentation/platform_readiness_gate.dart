import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/platform_readiness_controller.dart';
import '../application/platform_readiness_state.dart';

/// Pre-startup Material surface that reconciles live OS readiness on every
/// resume and only then builds the backend-dependent child subtree.
class PlatformReadinessGate extends ConsumerStatefulWidget {
  const PlatformReadinessGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PlatformReadinessGate> createState() =>
      _PlatformReadinessGateState();
}

class _PlatformReadinessGateState extends ConsumerState<PlatformReadinessGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(platformReadinessControllerProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final readiness = ref.watch(platformReadinessControllerProvider);
    return switch (readiness) {
      PlatformReadinessLoading() => const _ReadinessScaffold(
        child: Center(child: CircularProgressIndicator()),
      ),
      PlatformReadinessRequiresAllFilesAccess(:final failure) =>
        _ReadinessScaffold(
          title: 'Storage access required',
          body:
              'Argus needs access to manage files on this device so it can '
              'work with your local game library. Enable “Allow access to '
              'manage all files” in Android settings to continue.',
          primaryLabel: 'Open Android settings',
          onPrimary: () => ref
              .read(platformReadinessControllerProvider.notifier)
              .openAllFilesAccessSettings(),
          secondaryLabel: failure == null ? null : 'Retry',
          onSecondary: failure == null
              ? null
              : () => ref
                    .read(platformReadinessControllerProvider.notifier)
                    .refresh(),
        ),
      PlatformReadinessRequiresNotificationPermission(:final failure) =>
        _ReadinessScaffold(
          title: 'Background job notifications',
          body:
              'Allow notifications so Argus can show progress and controls '
              'for long-running work. You can continue if you decline.',
          primaryLabel: 'Continue',
          onPrimary: () => ref
              .read(platformReadinessControllerProvider.notifier)
              .requestNotificationPermission(),
          secondaryLabel: failure == null ? null : 'Retry',
          onSecondary: failure == null
              ? null
              : () => ref
                    .read(platformReadinessControllerProvider.notifier)
                    .refresh(),
        ),
      PlatformReadinessReady() => widget.child,
      PlatformReadinessUnavailable() => _ReadinessScaffold(
        title: 'Platform check unavailable',
        body: 'Argus could not verify Android storage access.',
        primaryLabel: 'Retry',
        onPrimary: () =>
            ref.read(platformReadinessControllerProvider.notifier).refresh(),
      ),
    };
  }
}

class _ReadinessScaffold extends StatelessWidget {
  const _ReadinessScaffold({
    this.title,
    this.body,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.child,
  });

  final String? title;
  final String? body;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child:
                  child ??
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (title case final String heading) ...<Widget>[
                        Text(
                          heading,
                          style: textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (body case final String copy) ...<Widget>[
                        Text(
                          copy,
                          style: textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (primaryLabel case final String label)
                        FilledButton(onPressed: onPrimary, child: Text(label)),
                      if (secondaryLabel case final String label)
                        TextButton(onPressed: onSecondary, child: Text(label)),
                    ],
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
