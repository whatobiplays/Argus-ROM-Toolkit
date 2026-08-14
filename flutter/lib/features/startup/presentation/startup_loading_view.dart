import 'package:argus/core/responsive/window_size_class.dart';
import 'package:flutter/material.dart';

/// Blocking pre-ready startup surface with indeterminate progress.
class StartupLoadingView extends StatelessWidget {
  /// Creates the startup loading surface.
  const StartupLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    final gutter = pageGutterFor(
      classifyWindowWidth(MediaQuery.sizeOf(context).width),
    );
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Semantics(
                    header: true,
                    child: Text(
                      'Argus ROM Toolkit',
                      style: textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Starting Argus…',
                    style: textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    liveRegion: true,
                    label: 'Argus is starting',
                    child: CircularProgressIndicator(),
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
