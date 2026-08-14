import 'package:argus/core/responsive/window_size_class.dart';
import 'package:flutter/material.dart';

/// Blocking surface while an intentional runtime shutdown is observable.
class ShuttingDownView extends StatelessWidget {
  /// Creates the shutting-down surface.
  const ShuttingDownView({super.key});

  @override
  Widget build(BuildContext context) {
    return _ShutdownScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('Closing Argus…', style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 24),
          Semantics(
            liveRegion: true,
            label: 'Argus is closing',
            child: CircularProgressIndicator(),
          ),
        ],
      ),
    );
  }
}

/// Terminal surface after authoritative stopped state is adopted.
class StoppedView extends StatelessWidget {
  /// Creates the stopped surface.
  const StoppedView({super.key});

  @override
  Widget build(BuildContext context) {
    return _ShutdownScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              'Argus has stopped',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'You can close the application window.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ShutdownScaffold extends StatelessWidget {
  const _ShutdownScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final gutter = pageGutterFor(
      classifyWindowWidth(MediaQuery.sizeOf(context).width),
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 32),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
