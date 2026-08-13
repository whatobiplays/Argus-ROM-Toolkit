import 'package:argus/core/responsive/window_size_class.dart';
import 'package:flutter/material.dart';

/// Presents the static Slice 004 Settings destination.
///
/// Appearance controls are intentionally deferred until the application
/// service and theme-authority slices are connected.
class SettingsPage extends StatelessWidget {
  /// Creates the static Settings destination.
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sizeClass = classifyWindowWidth(MediaQuery.sizeOf(context).width);
    final gutter = pageGutterFor(sizeClass);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 24),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Semantics(
                    header: true,
                    child: Text('Settings', style: textTheme.headlineMedium),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Appearance controls will be available after application '
                    'services are connected.',
                    style: textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
