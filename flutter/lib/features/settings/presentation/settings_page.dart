import 'package:argus/core/responsive/window_size_class.dart';
import 'package:argus/features/settings/application/appearance_settings_controller.dart';
import 'package:argus/features/settings/application/appearance_settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'appearance_messages.dart';
import 'theme_mode_control.dart';

/// Presents the real Phase 000 Appearance settings section.
///
/// Presentation watches the appearance controller and invokes only
/// [AppearanceSettingsController.selectThemeMode] and
/// [AppearanceSettingsController.retryAuthoritativeRead]; it never calls
/// client or bridge APIs directly.
class SettingsPage extends ConsumerWidget {
  /// Creates the Settings destination.
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeClass = classifyWindowWidth(MediaQuery.sizeOf(context).width);
    final gutter = pageGutterFor(sizeClass);
    final textTheme = Theme.of(context).textTheme;
    final appearance = ref.watch(appearanceSettingsControllerProvider);
    final state = appearance.value;
    final notifier = ref.read(appearanceSettingsControllerProvider.notifier);

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
                  if (state == null)
                    Center(
                      child: Semantics(
                        liveRegion: true,
                        label: 'Loading appearance settings',
                        child: const CircularProgressIndicator(),
                      ),
                    )
                  else
                    _AppearanceSection(state: state, notifier: notifier),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.state, required this.notifier});

  final AppearanceSettingsState state;
  final AppearanceSettingsController notifier;

  @override
  Widget build(BuildContext context) {
    final save = state.saveOperation;
    final synchronization = state.synchronization;
    final enabled =
        synchronization is AppearanceSynchronizationSynchronized &&
        save is! AppearanceSaveOperationSaving &&
        save is! AppearanceSaveOperationOutcomeUnknown &&
        save is! AppearanceSaveOperationCommittedButUnreconciled;
    final textTheme = Theme.of(context).textTheme;
    final saveFailure = switch (save) {
      AppearanceSaveOperationFailed(:final failure) => failure,
      AppearanceSaveOperationOutcomeUnknown(:final failure) => failure,
      AppearanceSaveOperationCommittedButUnreconciled(:final failure) =>
        failure,
      AppearanceSaveOperationIdle() || AppearanceSaveOperationSaving() => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Appearance', style: textTheme.titleLarge),
        const SizedBox(height: 8),
        ThemeModeControl(
          selectedMode: state.presented.themeMode,
          enabled: enabled,
          onChanged: notifier.selectThemeMode,
        ),
        const SizedBox(height: 8),
        if (save is AppearanceSaveOperationSaving)
          Semantics(
            liveRegion: true,
            label: 'Saving appearance settings',
            child: Text(
              'Saving appearance settings…',
              style: textTheme.bodyMedium,
            ),
          ),
        if (saveFailure != null)
          Semantics(
            liveRegion: true,
            label: appearanceSaveFailureMessage(saveFailure),
            child: Text(
              appearanceSaveFailureMessage(saveFailure),
              style: textTheme.bodyMedium,
            ),
          ),
        if (synchronization is AppearanceSynchronizationUncertain) ...<Widget>[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            label: appearanceUncertainMessage,
            child: Text(
              appearanceUncertainMessage,
              style: textTheme.bodyMedium,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: notifier.retryAuthoritativeRead,
              child: const Text('Retry'),
            ),
          ),
        ],
      ],
    );
  }
}
