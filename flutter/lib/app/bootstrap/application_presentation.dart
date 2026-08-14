import 'package:argus/core/client/client.dart' as client;
import 'package:argus/features/settings/settings_composition.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:flutter/material.dart' as material;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'application_presentation.g.dart';

/// Combined presentation readiness of the routed application shell.
enum ApplicationPresentationReadiness {
  /// Backend readiness has not been certified yet.
  preReady,

  /// Backend is ready but the first authoritative appearance read is pending.
  appearanceInitializing,

  /// The initial appearance read failed; no normal shell may be revealed.
  appearanceUnavailable,

  /// Backend readiness and appearance authority both exist.
  ready,
}

/// Projects backend readiness plus appearance authority onto shell admission.
@Riverpod(keepAlive: true)
ApplicationPresentationReadiness applicationPresentationReadiness(Ref ref) {
  if (ref.watch(appReadinessProvider) != AppReadiness.ready) {
    return ApplicationPresentationReadiness.preReady;
  }
  return ref
      .watch(appearanceSettingsControllerProvider)
      .when(
        data: (_) => ApplicationPresentationReadiness.ready,
        error: (_, _) => ApplicationPresentationReadiness.appearanceUnavailable,
        loading: () => ApplicationPresentationReadiness.appearanceInitializing,
      );
}

/// Projection of confirmed appearance authority onto the root theme mode.
///
/// Owns no mutable theme state; null means no confirmed authority exists yet
/// and the bootstrap presentation fallback remains in effect behind the gate.
@Riverpod(keepAlive: true)
material.ThemeMode? rootThemeMode(Ref ref) {
  final loaded = ref.watch(appearanceSettingsControllerProvider).value;
  final mode = switch (loaded) {
    AppearanceSettingsStateReady(:final confirmed) => confirmed.themeMode,
    _ => null,
  };
  return switch (mode) {
    client.ThemeMode.system => material.ThemeMode.system,
    client.ThemeMode.light => material.ThemeMode.light,
    client.ThemeMode.dark => material.ThemeMode.dark,
    null => null,
  };
}
