import 'package:argus/core/client/client.dart';
import 'package:argus/core/responsive/window_size_class.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/startup_controller.dart';
import '../application/startup_state.dart';
import 'presentation_seams.dart';
import 'startup_messages.dart';

/// Surface for the state where current runtime authority is unknown.
class RuntimeUnavailableView extends ConsumerStatefulWidget {
  /// Creates the runtime-unavailable surface.
  const RuntimeUnavailableView({required this.state, super.key});

  /// The authoritative unavailable state with last-known context.
  final StartupStateRuntimeUnavailable state;

  @override
  ConsumerState<RuntimeUnavailableView> createState() =>
      _RuntimeUnavailableViewState();
}

class _RuntimeUnavailableViewState
    extends ConsumerState<RuntimeUnavailableView> {
  final FocusNode _primaryFocus = FocusNode();
  bool _hasFocused = false;

  @override
  void initState() {
    super.initState();
    _requestFailureFocus();
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
    final reconciliation = widget.state.reconciliationOperation;
    final running = reconciliation is ReconciliationOperationStateRunning;
    final failure = reconciliation is ReconciliationOperationStateFailed
        ? reconciliation.error
        : null;

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
                      'Connection to Argus was lost',
                      style: textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Argus could not confirm its current state.',
                    style: textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  if (widget.state.lastKnownRuntime case final lastKnown?)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Last known status: '
                        '${lastKnownLifecycleLabel(lastKnown.lifecycle)}. '
                        'This is not current.',
                        style: textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 24),
                  if (running) ...<Widget>[
                    const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  FilledButton(
                    key: const ValueKey<String>('check-runtime-button'),
                    focusNode: _primaryFocus,
                    onPressed: running
                        ? null
                        : () {
                            ref
                                .read(startupControllerProvider.notifier)
                                .reconcileRuntime();
                          },
                    child: Text(running ? 'Checking…' : 'Check runtime again'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const ValueKey<String>(
                      'runtime-unavailable-exit-button',
                    ),
                    onPressed: () {
                      // Explicit frontend exit while authority is unknown;
                      // last-known identity is never retargeted and no
                      // reconciliation is required first.
                      ref.read(appTerminatorProvider)();
                    },
                    child: const Text('Exit'),
                  ),
                  if (failure case final ClientFailure error) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      operationFailureMessage(error),
                      style: textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
