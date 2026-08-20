import 'package:argus/core/client/client.dart';
import 'package:argus/core/responsive/window_size_class.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/startup_controller.dart';
import '../application/startup_state.dart';
import 'presentation_seams.dart';
import 'startup_messages.dart';

/// Inspectable failed-startup surface rendering only advertised actions.
class StartupFailureView extends ConsumerStatefulWidget {
  /// Creates the failed-startup recovery surface.
  const StartupFailureView({required this.state, super.key});

  /// The authoritative failed-runtime state for one generation.
  final StartupStateStartupFailed state;

  @override
  ConsumerState<StartupFailureView> createState() => _StartupFailureViewState();
}

class _StartupFailureViewState extends ConsumerState<StartupFailureView> {
  final FocusNode _primaryFocus = FocusNode();
  RuntimeInstanceId? _focusedGeneration;

  @override
  void initState() {
    super.initState();
    _requestFailureFocus();
  }

  @override
  void didUpdateWidget(StartupFailureView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.runtimeInstanceId != widget.state.runtimeInstanceId) {
      _focusedGeneration = null;
      _requestFailureFocus();
    }
  }

  @override
  void dispose() {
    _primaryFocus.dispose();
    super.dispose();
  }

  void _requestFailureFocus() {
    if (_focusedGeneration == widget.state.runtimeInstanceId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focusedGeneration == widget.state.runtimeInstanceId) {
        return;
      }
      _focusedGeneration = widget.state.runtimeInstanceId;
      _primaryFocus.requestFocus();
    });
  }

  bool _advertises(RecoveryActionKind kind) =>
      widget.state.failure.recoveryActions.any((action) => action.kind == kind);

  bool _renders(RecoveryActionKind kind) {
    if (!_advertises(kind)) return false;
    final capabilities = ref.watch(startupPresentationCapabilitiesProvider);
    return switch (kind) {
      RecoveryActionKind.exportDiagnostics => capabilities.diagnosticsExport,
      RecoveryActionKind.openDataDirectory => capabilities.openDataDirectory,
      _ => true,
    };
  }

  RecoveryActionKind get _primaryAction {
    if (_advertises(RecoveryActionKind.resetAppearanceSettings)) {
      return RecoveryActionKind.resetAppearanceSettings;
    }
    if (_advertises(RecoveryActionKind.retryStartup)) {
      return RecoveryActionKind.retryStartup;
    }
    return RecoveryActionKind.exit;
  }

  @override
  Widget build(BuildContext context) {
    final gutter = pageGutterFor(
      classifyWindowWidth(MediaQuery.sizeOf(context).width),
    );
    final textTheme = Theme.of(context).textTheme;
    final state = widget.state;
    final mutationRunning =
        state.recoveryOperation is RecoveryOperationStateRunning;
    final mutationError =
        state.recoveryOperation is RecoveryOperationStateFailed
        ? (state.recoveryOperation as RecoveryOperationStateFailed).error
        : null;
    final exportRunning = state.exportOperation is ExportOperationStateRunning;
    final exportResult = state.exportOperation is ExportOperationStateSucceeded
        ? (state.exportOperation as ExportOperationStateSucceeded).result
        : null;
    final exportError = state.exportOperation is ExportOperationStateFailed
        ? (state.exportOperation as ExportOperationStateFailed).error
        : null;
    final details = state.technicalDetails;
    final detailsLoading = details is TechnicalDetailsOperationStateLoading;
    final detailsLoaded = details is TechnicalDetailsOperationStateLoaded
        ? details.details
        : null;
    final detailsError = details is TechnicalDetailsOperationStateFailed
        ? details.error
        : null;
    final openRunning =
        state.openDirectoryOperation is OpenDirectoryOperationStateRunning;
    final openError =
        state.openDirectoryOperation is OpenDirectoryOperationStateFailed
        ? (state.openDirectoryOperation as OpenDirectoryOperationStateFailed)
              .error
        : null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 32),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Semantics(
                      header: true,
                      child: Text(
                        'Argus could not start',
                        style: textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      startupPhaseContext(state.failure.phase),
                      style: textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      messageForKey(state.failure.error.messageKey.value),
                      style: textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (mutationRunning) ...<Widget>[
                      Center(
                        child: Semantics(
                          liveRegion: true,
                          label: 'Startup recovery in progress',
                          child: const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_advertises(RecoveryActionKind.resetAppearanceSettings))
                      FilledButton(
                        key: const ValueKey<String>(
                          'reset-appearance-settings-button',
                        ),
                        focusNode:
                            _primaryAction ==
                                RecoveryActionKind.resetAppearanceSettings
                            ? _primaryFocus
                            : null,
                        onPressed: mutationRunning
                            ? null
                            : () => _confirmResetAppearance(context),
                        child: const Text('Reset Appearance Settings'),
                      ),
                    if (_advertises(
                      RecoveryActionKind.retryStartup,
                    )) ...<Widget>[
                      if (_advertises(
                        RecoveryActionKind.resetAppearanceSettings,
                      ))
                        const SizedBox(height: 12),
                      FilledButton(
                        key: const ValueKey<String>('retry-startup-button'),
                        focusNode:
                            _primaryAction == RecoveryActionKind.retryStartup
                            ? _primaryFocus
                            : null,
                        onPressed: mutationRunning
                            ? null
                            : () {
                                ref
                                    .read(startupControllerProvider.notifier)
                                    .retryStartup();
                              },
                        child: const Text('Retry Startup'),
                      ),
                    ],
                    if (_renders(RecoveryActionKind.exportDiagnostics))
                      ..._exportAction(
                        context,
                        mutationRunning,
                        exportRunning,
                        exportError,
                      ),
                    if (_advertises(RecoveryActionKind.copyTechnicalDetails))
                      ..._detailsActions(
                        context,
                        textTheme,
                        mutationRunning,
                        detailsLoading,
                        detailsLoaded,
                        detailsError,
                      ),
                    if (_renders(RecoveryActionKind.openDataDirectory))
                      ..._openDirectoryAction(
                        context,
                        mutationRunning,
                        openRunning,
                        openError,
                      ),
                    if (_advertises(RecoveryActionKind.exit)) ...<Widget>[
                      if (_renders(RecoveryActionKind.retryStartup) ||
                          _renders(
                            RecoveryActionKind.resetAppearanceSettings,
                          ) ||
                          _renders(RecoveryActionKind.exportDiagnostics) ||
                          _renders(RecoveryActionKind.copyTechnicalDetails) ||
                          _renders(RecoveryActionKind.openDataDirectory))
                        const SizedBox(height: 12),
                      TextButton(
                        key: const ValueKey<String>('exit-application-button'),
                        focusNode: _primaryAction == RecoveryActionKind.exit
                            ? _primaryFocus
                            : null,
                        onPressed: mutationRunning
                            ? null
                            : () {
                                ref
                                    .read(startupControllerProvider.notifier)
                                    .requestExit();
                              },
                        child: const Text('Exit'),
                      ),
                    ],
                    if (mutationError
                        case final ClientFailure error) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        operationFailureMessage(error),
                        style: textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (exportResult
                        case final DiagnosticsExport result) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        'Diagnostics exported to ${result.destinationClassification}.',
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
      ),
    );
  }

  List<Widget> _exportAction(
    BuildContext context,
    bool mutationRunning,
    bool running,
    ClientFailure? error,
  ) {
    return <Widget>[
      const SizedBox(height: 12),
      OutlinedButton(
        key: const ValueKey<String>('export-diagnostics-button'),
        onPressed: (mutationRunning || running)
            ? null
            : () => _exportDiagnostics(context),
        child: Text(running ? 'Exporting…' : 'Export Diagnostics'),
      ),
      if (error case final ClientFailure failure) ...<Widget>[
        const SizedBox(height: 8),
        Text(operationFailureMessage(failure), textAlign: TextAlign.center),
      ],
    ];
  }

  List<Widget> _detailsActions(
    BuildContext context,
    TextTheme textTheme,
    bool mutationRunning,
    bool loading,
    TechnicalDetails? loaded,
    ClientFailure? error,
  ) {
    return <Widget>[
      const SizedBox(height: 12),
      OutlinedButton(
        key: const ValueKey<String>('copy-technical-details-button'),
        onPressed: (mutationRunning || loading)
            ? null
            : () => _copyTechnicalDetails(context),
        child: Text(loading ? 'Loading…' : 'Copy Technical Details'),
      ),
      const SizedBox(height: 4),
      ExpansionTile(
        key: const ValueKey<String>('technical-details-disclosure'),
        title: const Text('Technical details'),
        onExpansionChanged: (expanded) {
          if (expanded) {
            ref.read(startupControllerProvider.notifier).loadTechnicalDetails();
          }
        },
        children: <Widget>[
          if (loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (loaded case final TechnicalDetails details)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                details.text,
                key: const ValueKey<String>('technical-details-text'),
                style: textTheme.bodySmall,
              ),
            )
          else if (error case final ClientFailure failure)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(operationFailureMessage(failure)),
            )
          else
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Technical details are not loaded yet.'),
            ),
        ],
      ),
    ];
  }

  List<Widget> _openDirectoryAction(
    BuildContext context,
    bool mutationRunning,
    bool running,
    ClientFailure? error,
  ) {
    return <Widget>[
      const SizedBox(height: 12),
      OutlinedButton(
        key: const ValueKey<String>('open-data-directory-button'),
        onPressed: (mutationRunning || running)
            ? null
            : () {
                ref
                    .read(startupControllerProvider.notifier)
                    .openDataDirectory();
              },
        child: Text(running ? 'Opening…' : 'Open Data Directory'),
      ),
      if (error case final ClientFailure failure) ...<Widget>[
        const SizedBox(height: 8),
        Text(operationFailureMessage(failure), textAlign: TextAlign.center),
      ],
    ];
  }

  Future<void> _confirmResetAppearance(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reset appearance settings?'),
          content: const Text(
            'Saved appearance settings will be reset to System. '
            'No other data is changed.',
          ),
          actions: <Widget>[
            TextButton(
              key: const ValueKey<String>('reset-cancel-button'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey<String>('reset-confirm-button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );
    if (confirmed ?? false) {
      await ref
          .read(startupControllerProvider.notifier)
          .resetAppearanceSettings();
    }
  }

  Future<void> _exportDiagnostics(BuildContext context) async {
    final capabilities = ref.read(startupPresentationCapabilitiesProvider);
    if (capabilities.diagnosticsSharing) {
      await ref
          .read(startupControllerProvider.notifier)
          .exportDiagnosticsForSharing();
      return;
    }
    final picker = ref.read(diagnosticsDestinationPickerProvider);
    final destination = await picker(
      suggestedName: 'argus-startup-diagnostics.zip',
    );
    if (destination == null) return;
    await ref
        .read(startupControllerProvider.notifier)
        .exportDiagnostics(destination: destination);
  }

  Future<void> _copyTechnicalDetails(BuildContext context) async {
    final controller = ref.read(startupControllerProvider.notifier);
    final current = ref.read(startupControllerProvider).value;
    if (current is! StartupStateStartupFailed) return;
    String? text;
    final details = current.technicalDetails;
    if (details is TechnicalDetailsOperationStateLoaded) {
      text = details.details.text;
    } else if (details is TechnicalDetailsOperationStateIdle ||
        details is TechnicalDetailsOperationStateFailed) {
      await controller.loadTechnicalDetails();
      final latest = ref.read(startupControllerProvider).value;
      if (latest is StartupStateStartupFailed &&
          latest.technicalDetails is TechnicalDetailsOperationStateLoaded) {
        text = (latest.technicalDetails as TechnicalDetailsOperationStateLoaded)
            .details
            .text;
      }
    }
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Copied technical details')));
    }
  }
}
