import 'package:argus/app/routing/app_destination.dart';
import 'package:argus/app/shell/application_shell.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/jobs/jobs.dart';
import 'package:argus/features/library/library.dart';
import 'package:argus/features/settings/settings.dart';
import 'package:argus/features/sources/sources.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'not_found_page.dart';

part 'app_routes.g.dart';

/// Derives shell selection from the typed route location.
AppDestination? destinationForUri(Uri uri) {
  if (uri.path == '/library' ||
      uri.path.startsWith('/library/') ||
      uri.path.startsWith('/games/')) {
    return AppDestination.library;
  }
  if (uri.path == '/settings') {
    return AppDestination.settings;
  }
  if (uri.path == '/sources' || uri.path.startsWith('/sources/')) {
    return AppDestination.sources;
  }
  if (uri.path == '/jobs' || uri.path.startsWith('/jobs/')) {
    return AppDestination.jobs;
  }
  return null;
}

/// Canonical entry point owned by the global readiness redirect.
@TypedGoRoute<RootRoute>(path: '/')
class RootRoute extends GoRouteData with $RootRoute {
  /// Creates the canonical root route.
  const RootRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const SizedBox.shrink();
}

/// Product onboarding is outside the ready-state shell and is driven by the
/// query-authoritative native onboarding projection.
@TypedGoRoute<LibraryOnboardingRoute>(path: '/onboarding/library')
class LibraryOnboardingRoute extends GoRouteData with $LibraryOnboardingRoute {
  const LibraryOnboardingRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return LibraryOnboardingPage(
      onOpenLibrary: () => const LibraryRoute().go(context),
      onOpenJob: (jobRunId) =>
          JobsDetailRoute(jobRunId: jobRunId.value).go(context),
    );
  }
}

/// Hosts the production semantic destinations in the persistent shell.
@TypedShellRoute<ApplicationShellRoute>(
  routes: <TypedRoute<RouteData>>[
    TypedGoRoute<LibraryRoute>(
      path: '/library',
      routes: <TypedRoute<RouteData>>[
        TypedGoRoute<LibraryPlatformRoute>(path: 'platforms/:platformId'),
        TypedGoRoute<LibrarySourceRoute>(path: 'sources/:sourceId'),
        TypedGoRoute<LibraryRootScopeRoute>(
          path: 'library-roots/:libraryRootId',
        ),
      ],
    ),
    TypedGoRoute<GameDetailRoute>(path: '/games/:gameId'),
    TypedGoRoute<SettingsRoute>(path: '/settings'),
    TypedGoRoute<SourcesRoute>(
      path: '/sources',
      routes: <TypedRoute<RouteData>>[
        TypedGoRoute<SourcesRootRoute>(path: 'roots/:rootId'),
      ],
    ),
    TypedGoRoute<JobsRoute>(
      path: '/jobs',
      routes: <TypedRoute<RouteData>>[
        TypedGoRoute<JobsDetailRoute>(path: ':jobRunId'),
      ],
    ),
  ],
)
class ApplicationShellRoute extends ShellRouteData {
  /// Creates the production application shell route.
  const ApplicationShellRoute();

  @override
  Widget builder(BuildContext context, GoRouterState state, Widget navigator) {
    return BranchAwareShell(
      currentUri: state.uri,
      currentDestination: destinationForUri(state.uri),
      includeLibrary: true,
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
    return SettingsPage(
      onOpenJob: (jobRunId) =>
          JobsDetailRoute(jobRunId: jobRunId.value).go(context),
    );
  }
}

/// Typed unscoped Library destination.
class LibraryRoute extends GoRouteData with $LibraryRoute {
  const LibraryRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) => LibraryPage(
    scope: const LibraryScopeAll(),
    onOpenAll: () => const LibraryRoute().go(context),
    onOpenGame: (gameId) => GameDetailRoute(gameId: gameId.value).go(context),
    onOpenSources: () => const SourcesRoute().go(context),
    onOpenJob: (jobRunId) =>
        JobsDetailRoute(jobRunId: jobRunId.value).go(context),
  );
}

/// Platform scope route. The raw parameter is retained in [LibraryScope] and
/// is never downgraded to the unscoped Library query.
class LibraryPlatformRoute extends GoRouteData with $LibraryPlatformRoute {
  const LibraryPlatformRoute({required this.platformId});

  final String platformId;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    try {
      PlatformId.fromWire(platformId);
    } on ClientFailure {
      return _invalidLibraryScope(context, state.uri.path);
    }
    return _scopedLibrary(context, LibraryScope.platform(platformId));
  }
}

/// Logical source scope route. It is intentionally distinct from operational
/// Sources hierarchy routes.
class LibrarySourceRoute extends GoRouteData with $LibrarySourceRoute {
  const LibrarySourceRoute({required this.sourceId});

  final String sourceId;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    if (!_isValidScopeToken(sourceId)) {
      return _invalidLibraryScope(context, state.uri.path);
    }
    return _scopedLibrary(context, LibraryScope.source(sourceId));
  }
}

/// Configured-root scope route for logical Game browsing.
class LibraryRootScopeRoute extends GoRouteData with $LibraryRootScopeRoute {
  const LibraryRootScopeRoute({required this.libraryRootId});

  final String libraryRootId;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    final id = LibraryRootId.tryParse(libraryRootId);
    if (id == null) {
      return _invalidLibraryScope(context, state.uri.path);
    }
    return _scopedLibrary(context, LibraryScope.libraryRoot(id.value));
  }
}

Widget _scopedLibrary(BuildContext context, LibraryScope scope) => LibraryPage(
  scope: scope,
  onOpenAll: () => const LibraryRoute().go(context),
  onOpenGame: (gameId) => GameDetailRoute(gameId: gameId.value).go(context),
  onOpenSources: () => const SourcesRoute().go(context),
  onOpenJob: (jobRunId) =>
      JobsDetailRoute(jobRunId: jobRunId.value).go(context),
);

Widget _invalidLibraryScope(BuildContext context, String path) =>
    AppRouteErrorPage(
      kind: RouteLocationFailure.invalidRouteData,
      path: path,
      title: 'Invalid Library scope',
      message: 'The requested Library scope is not a valid canonical identity.',
      actionLabel: 'Go to Library',
      onAction: () => const LibraryRoute().go(context),
    );

bool _isValidScopeToken(String value) =>
    value.isNotEmpty &&
    value.length <= 256 &&
    RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value);

/// Typed production Game detail route.
class GameDetailRoute extends GoRouteData with $GameDetailRoute {
  const GameDetailRoute({required this.gameId});

  final String gameId;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    final id = GameId.tryParse(gameId);
    if (id == null) {
      return _invalidLibraryScope(context, state.uri.path);
    }
    return GameDetailPage(
      gameId: id,
      onMissingGame: () => const LibraryRoute().go(context),
      onOpenGame: (canonicalId) =>
          GameDetailRoute(gameId: canonicalId.value).go(context),
      onOpenJob: (jobRunId) =>
          JobsDetailRoute(jobRunId: jobRunId.value).go(context),
    );
  }
}

/// Typed production Sources destination.
class SourcesRoute extends GoRouteData with $SourcesRoute {
  /// Creates the Sources route.
  const SourcesRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return SourcesPage(
      onOpenRoot: (rootId) =>
          SourcesRootRoute(rootId: rootId.value).go(context),
      onOpenJob: (jobRunId) =>
          JobsDetailRoute(jobRunId: jobRunId.value).go(context),
    );
  }
}

/// Typed production configured-root detail route.
class SourcesRootRoute extends GoRouteData with $SourcesRootRoute {
  /// Creates the root-detail route for one raw path parameter.
  const SourcesRootRoute({required this.rootId});

  /// The raw route parameter. Parsing happens at the routing boundary; a
  /// malformed value renders the controlled invalid-location surface and
  /// never reaches feature state.
  final String rootId;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    final id = LibraryRootId.tryParse(rootId);
    if (id == null) {
      return AppInvalidRoutePage(
        path: state.uri.path,
        onReturnToSources: () => const SourcesRoute().go(context),
      );
    }
    return SourcesRootDetailPage(
      rootId: id,
      onMissingRoot: () => const SourcesRoute().go(context),
      onRemoved: () => const SourcesRoute().go(context),
      onOpenJob: (jobRunId) =>
          JobsDetailRoute(jobRunId: jobRunId.value).go(context),
      onOpenRoot: (rootId) =>
          SourcesRootRoute(rootId: rootId.value).go(context),
    );
  }
}

/// Typed production Jobs destination.
class JobsRoute extends GoRouteData with $JobsRoute {
  /// Creates the Jobs route.
  const JobsRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return JobsPage(
      onOpenJob: (jobRunId) =>
          JobsDetailRoute(jobRunId: jobRunId.value).go(context),
    );
  }
}

/// Typed production job-detail route.
class JobsDetailRoute extends GoRouteData with $JobsDetailRoute {
  /// Creates the job-detail route.
  const JobsDetailRoute({required this.jobRunId});

  /// The raw route parameter. Parsing happens at the routing boundary.
  final String jobRunId;

  @override
  Widget build(BuildContext context, GoRouterState state) {
    final id = JobRunId.tryParse(jobRunId);
    if (id == null) {
      return AppInvalidRoutePage(
        path: state.uri.path,
        onReturnToSources: () => const JobsRoute().go(context),
      );
    }
    return JobDetailPage(
      jobRunId: id,
      onMissingJob: () => const JobsRoute().go(context),
      onOpenJob: (jobRunId) =>
          JobsDetailRoute(jobRunId: jobRunId.value).go(context),
    );
  }
}
