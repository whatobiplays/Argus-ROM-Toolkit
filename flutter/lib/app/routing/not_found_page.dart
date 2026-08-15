import 'package:flutter/material.dart';

/// Distinguishable route-level failure semantics (SPEC-FE-004 §89–91).
enum RouteLocationFailure {
  /// The router recognized no route for the location.
  unknownLocation,

  /// A recognized route pattern carried malformed required route data.
  invalidRouteData,
}

/// Shared controlled route-error surface for both failure kinds.
///
/// The two kinds share design-system components but remain distinguishable
/// through [RouteLocationFailure] for tests and diagnostics. Presentation is
/// always sanitized: no stack traces, raw router exceptions, generated-code
/// internals, or implementation class names.
class AppRouteErrorPage extends StatelessWidget {
  const AppRouteErrorPage({
    required this.kind,
    required this.path,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final RouteLocationFailure kind;
  final String path;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final summary = _sanitizePath(path);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 12),
                Text('$message\n\n$summary'),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.arrow_back),
                  label: Text(actionLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Displays a controlled response when the router cannot match a location.
class AppNotFoundPage extends StatelessWidget {
  /// Creates the not-found surface for a presentation-safe path summary.
  const AppNotFoundPage({
    required this.path,
    required this.onReturnToSettings,
    super.key,
  });

  /// The unmatched URI path, excluding query and fragment content.
  final String path;

  /// Returns the user to the one production destination.
  final VoidCallback onReturnToSettings;

  @override
  Widget build(BuildContext context) {
    return AppRouteErrorPage(
      kind: RouteLocationFailure.unknownLocation,
      path: path,
      title: 'Page not found',
      message: 'No page exists at this location.',
      actionLabel: 'Go to Settings',
      onAction: onReturnToSettings,
    );
  }
}

/// Controlled invalid-location surface for malformed recognized route data.
class AppInvalidRoutePage extends StatelessWidget {
  /// Creates the invalid-location surface with a Sources recovery action.
  const AppInvalidRoutePage({
    required this.path,
    required this.onReturnToSources,
    super.key,
  });

  /// The sanitized presentation-safe path summary.
  final String path;

  /// Returns the user to the Sources destination.
  final VoidCallback onReturnToSources;

  @override
  Widget build(BuildContext context) {
    return AppRouteErrorPage(
      kind: RouteLocationFailure.invalidRouteData,
      path: path,
      title: 'Invalid location',
      message: 'This library-folder location is not valid.',
      actionLabel: 'Go to Sources',
      onAction: onReturnToSources,
    );
  }
}

String _sanitizePath(String value) {
  final safeCodePoints = value.runes
      .where((codePoint) => codePoint >= 0x20 && codePoint != 0x7f)
      .toList(growable: false);
  final isTruncated = safeCodePoints.length > 77;
  final visibleCodePoints = isTruncated
      ? safeCodePoints.take(77)
      : safeCodePoints;
  final summary = String.fromCharCodes(visibleCodePoints);

  if (summary.isEmpty) {
    return '/';
  }
  return isTruncated ? '$summary...' : summary;
}
