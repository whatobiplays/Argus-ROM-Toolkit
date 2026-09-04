import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/app/platform/platform_host.dart';
import 'package:argus/core/client/client.dart' as client;
import 'package:argus/features/library/application/library_onboarding_routing.dart';
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

  /// The Library capability is not available in this client generation.
  libraryUnavailable,

  /// The first authoritative onboarding read is pending.
  onboardingInitializing,

  /// The first authoritative onboarding read failed.
  onboardingUnavailable,

  /// Authoritative onboarding requires user completion.
  onboardingRequired,

  /// Backend, appearance, and onboarding authority all exist.
  ready,
}

/// Projects backend readiness, appearance, and Library onboarding authority
/// onto shell admission.
@Riverpod(keepAlive: true)
ApplicationPresentationReadiness applicationPresentationReadiness(Ref ref) {
  if (ref.watch(platformReadinessRequiredProvider) &&
      ref.watch(platformReadinessControllerProvider)
          is! PlatformReadinessReady) {
    return ApplicationPresentationReadiness.preReady;
  }
  if (ref.watch(appReadinessProvider) != AppReadiness.ready) {
    return ApplicationPresentationReadiness.preReady;
  }
  return ref
      .watch(appearanceSettingsControllerProvider)
      .when(
        data: (_) {
          if (!ref.watch(argusClientProvider).supportsLibraryPhase003) {
            return ApplicationPresentationReadiness.libraryUnavailable;
          }
          final onboarding = ref.watch(libraryOnboardingRoutingProvider);
          if (onboarding.hasError) {
            return ApplicationPresentationReadiness.onboardingUnavailable;
          }
          if (onboarding.isLoading) {
            return ApplicationPresentationReadiness.onboardingInitializing;
          }
          return switch (onboarding.requireValue.status) {
            LibraryOnboardingRoutingStatus.preReady =>
              ApplicationPresentationReadiness.onboardingInitializing,
            LibraryOnboardingRoutingStatus.required =>
              ApplicationPresentationReadiness.onboardingRequired,
            LibraryOnboardingRoutingStatus.complete =>
              ApplicationPresentationReadiness.ready,
          };
        },
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
