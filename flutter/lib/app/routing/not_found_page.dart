import 'package:flutter/material.dart';

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
    final summary = _sanitizePath(path);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Semantics(
                  header: true,
                  child: Text(
                    'Page not found',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 12),
                Text('No page exists at $summary.'),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onReturnToSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Go to Settings'),
                ),
              ],
            ),
          ),
        ),
      ),
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
