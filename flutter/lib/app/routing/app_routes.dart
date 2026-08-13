import 'package:argus/app/routing/app_destination.dart';
import 'package:argus/app/shell/application_shell.dart';
import 'package:argus/features/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

part 'app_routes.g.dart';

/// Derives shell selection from the typed Settings route location.
AppDestination? destinationForUri(Uri uri) {
  return uri.path == const SettingsRoute().location
      ? AppDestination.settings
      : null;
}

/// Canonical entry point that forwards the application to Settings.
@TypedGoRoute<RootRoute>(path: '/')
class RootRoute extends GoRouteData with $RootRoute {
  /// Creates the canonical root route.
  const RootRoute();

  @override
  String? redirect(BuildContext context, GoRouterState state) {
    return const SettingsRoute().location;
  }
}

/// Hosts the production semantic destinations in the persistent shell.
@TypedShellRoute<ApplicationShellRoute>(
  routes: <TypedRoute<RouteData>>[
    TypedGoRoute<SettingsRoute>(path: '/settings'),
  ],
)
class ApplicationShellRoute extends ShellRouteData {
  /// Creates the production application shell route.
  const ApplicationShellRoute();

  @override
  Widget builder(BuildContext context, GoRouterState state, Widget navigator) {
    return ApplicationShell(
      currentDestination: destinationForUri(state.uri),
      onSettingsSelected: () => const SettingsRoute().go(context),
      child: navigator,
    );
  }
}

/// Typed production Settings destination.
class SettingsRoute extends GoRouteData with $SettingsRoute {
  /// Creates the Settings route.
  const SettingsRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const SettingsPage();
  }
}
