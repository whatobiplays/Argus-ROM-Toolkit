import 'package:argus/core/responsive/window_size_class.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/startup_controller.dart';
import 'presentation_seams.dart';
import 'startup_messages.dart';

/// Safe surface for pre-runtime client/bootstrap failure.
class BootstrapFailureView extends ConsumerStatefulWidget {
  /// Creates the bootstrap-failure surface.
  const BootstrapFailureView({required this.failure, super.key});

  /// The lossless typed client failure that prevented a runtime contract.
  final Object failure;

  @override
  ConsumerState<BootstrapFailureView> createState() =>
      _BootstrapFailureViewState();
}

class _BootstrapFailureViewState extends ConsumerState<BootstrapFailureView> {
  final FocusNode _primaryFocus = FocusNode();
  bool _hasFocused = false;

  @override
  void initState() {
    super.initState();
    _requestFailureFocus();
  }

  @override
  void didUpdateWidget(BootstrapFailureView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.failure, widget.failure)) {
      _hasFocused = false;
      _requestFailureFocus();
    }
  }

  @override
  void dispose() {
    _primaryFocus.dispose();
    super.dispose();
  }

  void _requestFailureFocus() {
    if (_hasFocused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasFocused) return;
      _hasFocused = true;
      _primaryFocus.requestFocus();
    });
  }

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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Semantics(
                    header: true,
                    child: Text(
                      'Argus could not initialize',
                      style: textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    bootstrapFailureMessage(widget.failure),
                    style: textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const ValueKey<String>('retry-initialization-button'),
                    focusNode: _primaryFocus,
                    onPressed: () {
                      ref
                          .read(startupControllerProvider.notifier)
                          .retryInitialization();
                    },
                    child: const Text('Retry Initialization'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const ValueKey<String>('bootstrap-exit-button'),
                    onPressed: () {
                      ref.read(appTerminatorProvider)();
                    },
                    child: const Text('Exit'),
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
