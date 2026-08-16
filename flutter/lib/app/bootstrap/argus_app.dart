import 'package:argus/app/bootstrap/application_presentation.dart';
import 'package:argus/app/bootstrap/application_presentation_gate.dart';
import 'package:argus/app/platform/platform_host.dart';
import 'package:argus/app/routing/app_router.dart';
import 'package:argus/core/design_system/argus_theme.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Composes the application-owned router, Material 3 themes, and the
/// pre-ready startup/recovery admission gate.
class ArgusApp extends ConsumerWidget {
  /// Creates the application root.
  const ArgusApp({this.platformReadinessRequired = false, super.key});

  /// Whether backend-dependent presentation must wait for platform readiness.
  final bool platformReadinessRequired;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final platformReady =
        !platformReadinessRequired ||
        ref.watch(platformReadinessControllerProvider)
            is PlatformReadinessReady;
    // The theme chain reaches appearance settings and therefore the startup
    // runtime; it must not be watched before platform readiness.
    final authoritativeThemeMode = platformReady
        ? ref.watch(rootThemeModeProvider)
        : null;

    return MaterialApp.router(
      title: 'Argus ROM Toolkit',
      theme: ArgusTheme.light,
      darkTheme: ArgusTheme.dark,
      themeAnimationDuration: Duration.zero,
      themeMode: authoritativeThemeMode ?? ThemeMode.system,
      builder: (context, child) {
        final startup = StartupGate(
          child: ApplicationPresentationGate(child: child!),
        );
        return platformReadinessRequired
            ? PlatformReadinessGate(child: startup)
            : startup;
      },
      routerConfig: router,
    );
  }
}
