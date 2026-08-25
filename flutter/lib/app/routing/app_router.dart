import 'package:argus/app/routing/app_routes.dart';
import 'package:argus/app/routing/not_found_page.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/core/client/client.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

/// Provides the app-owned router as a dependency-composition seam.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final refresh = _RouterRefresh();
  final router = GoRouter(
    routes: $appRoutes,
    refreshListenable: refresh,
    redirect: (context, state) => _redirectForLibraryOnboarding(ref, state),
    errorBuilder: (context, state) => AppNotFoundPage(
      path: state.uri.path,
      onReturnToLibrary: () => const LibraryRoute().go(context),
    ),
  );
  ref.onDispose(() {
    refresh.dispose();
    router.dispose();
  });
  return router;
}

/// Re-runs router admission when the presentation gate publishes readiness.
/// The router owns location decisions; the client owns the authoritative
/// onboarding facts.
final class _RouterRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}

Future<String?> _redirectForLibraryOnboarding(
  Ref ref,
  GoRouterState state,
) async {
  final onboardingPath = const LibraryOnboardingRoute().location;
  final isOnboarding = state.uri.path == onboardingPath;
  try {
    final client = ref.read(argusClientProvider);
    if (client.boundGeneration == null) return null;
    if (!client.supportsLibraryPhase003) {
      return isOnboarding ? const SettingsRoute().location : null;
    }
    final onboarding = await client.onboarding.getState();
    if (onboarding.complete) {
      return isOnboarding ? const LibraryRoute().location : null;
    }
    return isOnboarding ? null : onboardingPath;
  } on ClientFailure {
    // The only truthful ready-state fallback is the controlled onboarding
    // surface, where the user can retry the authoritative query.
    return isOnboarding ? null : onboardingPath;
  } on Object {
    // Startup and platform readiness are owned by the app bootstrap. Until
    // they are complete, leave the current location for the startup gate.
    return null;
  }
}
