import 'package:argus/core/client/client.dart' show ThemeMode;
import 'package:flutter/material.dart' hide ThemeMode;

/// Standard Material single-selection control for the Theme Mode setting.
///
/// Consumes loaded feature state and callbacks only; it never calls client or
/// bridge APIs directly.
class ThemeModeControl extends StatelessWidget {
  /// Creates the Theme Mode control.
  const ThemeModeControl({
    required this.selectedMode,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  /// The currently presented theme mode.
  final ThemeMode selectedMode;

  /// Whether user selection is currently admissible.
  final bool enabled;

  /// Callback invoked with an admitted selection.
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            'Theme Mode',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 4),
        RadioGroup<ThemeMode>(
          groupValue: selectedMode,
          onChanged: (value) => onChanged(value!),
          child: Column(
            children: <Widget>[
              RadioListTile<ThemeMode>(
                value: ThemeMode.system,
                enabled: enabled,
                title: const Text('System'),
                subtitle: const Text(
                  'Follows your operating system appearance.',
                ),
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.light,
                enabled: enabled,
                title: const Text('Light'),
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.dark,
                enabled: enabled,
                title: const Text('Dark'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
