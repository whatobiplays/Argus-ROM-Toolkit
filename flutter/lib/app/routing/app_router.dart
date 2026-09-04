import 'package:argus/app/bootstrap/application_presentation.dart';
import 'package:argus/app/routing/app_destination.dart';
import 'package:argus/app/routing/app_routes.dart';
import 'package:argus/app/routing/not_found_page.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

/// Provides the app-owned router as a dependency-composition seam.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final refresh = _RouterRefresh();
  ref.listen<ApplicationPresentationReadiness>(
    applicationPresentationReadinessProvider,
    (previous, next) {
      if (previous != next) {
        refresh.notify();
      }
    },
  );
  final router = GoRouter(
    routes: $appRoutes,
    refreshListenable: refresh,
    redirect: (context, state) => _redirectForPresentationReadiness(
      ref.read(applicationPresentationReadinessProvider),
      state,
    ),
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

String? _redirectForPresentationReadiness(
  ApplicationPresentationReadiness readiness,
  GoRouterState state,
) {
  final path = state.uri.path;
  final rootPath = const RootRoute().location;
  final onboardingPath = const LibraryOnboardingRoute().location;
  final libraryPath = const LibraryRoute().location;
  final settingsPath = const SettingsRoute().location;
  final isRoot = path == rootPath;
  final isOnboarding = state.uri.path == onboardingPath;
  final isLibraryDestination =
      destinationForUri(state.uri) == AppDestination.library;

  return switch (readiness) {
    ApplicationPresentationReadiness.libraryUnavailable =>
      isRoot || isOnboarding || isLibraryDestination ? settingsPath : null,
    ApplicationPresentationReadiness.onboardingRequired =>
      isOnboarding ? null : onboardingPath,
    ApplicationPresentationReadiness.ready =>
      isRoot || isOnboarding ? libraryPath : null,
    ApplicationPresentationReadiness.preReady ||
    ApplicationPresentationReadiness.appearanceInitializing ||
    ApplicationPresentationReadiness.appearanceUnavailable ||
    ApplicationPresentationReadiness.onboardingInitializing ||
    ApplicationPresentationReadiness.onboardingUnavailable => null,
  };
}
