import 'package:argus/app/routing/app_routes.dart';
import 'package:argus/app/routing/not_found_page.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

/// Provides the app-owned router as a dependency-composition seam.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final router = GoRouter(
    routes: $appRoutes,
    errorBuilder: (context, state) => AppNotFoundPage(
      path: state.uri.path,
      onReturnToSettings: () => const SettingsRoute().go(context),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
}
