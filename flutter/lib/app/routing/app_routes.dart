import 'package:argus/app/routing/app_destination.dart';
import 'package:argus/app/shell/application_shell.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/jobs/jobs.dart';
import 'package:argus/features/settings/settings.dart';
import 'package:argus/features/sources/sources.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'not_found_page.dart';

part 'app_routes.g.dart';

/// Derives shell selection from the typed route location.
AppDestination? destinationForUri(Uri uri) {
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

/// Canonical entry point that forwards the application to the ready default.
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
  /// Creates the job-detail route for one raw path parameter.
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
