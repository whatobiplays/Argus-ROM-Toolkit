import 'package:argus/core/client/client.dart';
import 'package:flutter/material.dart';

import 'appearance_messages.dart';

/// Stable centered progress surface shown while the first authoritative
/// appearance snapshot is loading.
class AppearanceInitializationView extends StatelessWidget {
  /// Creates the appearance initialization surface.
  const AppearanceInitializationView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Loading appearance settings…',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

/// Typed failure surface for an unrecoverable initial appearance load.
///
/// Owns no client or lifecycle dependency; retry and exit arrive as callbacks
/// from app composition.
class AppearanceInitializationFailureView extends StatelessWidget {
  /// Creates the initial appearance failure surface.
  const AppearanceInitializationFailureView({
    required this.failure,
    required this.onRetry,
    required this.onExit,
    super.key,
  });

  /// The typed failure that prevented first-shell presentation.
  final ClientFailure failure;

  /// Issues a read-only retry through the appearance controller.
  final VoidCallback onRetry;

  /// Exits the application through the composition termination seam.
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Appearance unavailable',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  appearanceLoadFailureMessage(failure),
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
                const SizedBox(height: 8),
                TextButton(onPressed: onExit, child: const Text('Exit')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
