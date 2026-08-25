// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_routes.dart';

// **************************************************************************
// GoRouterGenerator
// **************************************************************************

List<RouteBase> get $appRoutes => [
  $rootRoute,
  $libraryOnboardingRoute,
  $applicationShellRoute,
];

RouteBase get $rootRoute => GoRouteData.$route(
  path: '/',
  hasOverriddenOnExit: false,
  factory: $RootRoute._fromState,
);

mixin $RootRoute on GoRouteData {
  static RootRoute _fromState(GoRouterState state) => const RootRoute();

  @override
  String get location => GoRouteData.$location('/');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $libraryOnboardingRoute => GoRouteData.$route(
  path: '/onboarding/library',
  hasOverriddenOnExit: false,
  factory: $LibraryOnboardingRoute._fromState,
);

mixin $LibraryOnboardingRoute on GoRouteData {
  static LibraryOnboardingRoute _fromState(GoRouterState state) =>
      const LibraryOnboardingRoute();

  @override
  String get location => GoRouteData.$location('/onboarding/library');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

RouteBase get $applicationShellRoute => ShellRouteData.$route(
  factory: $ApplicationShellRouteExtension._fromState,
  routes: [
    GoRouteData.$route(
      path: '/library',
      hasOverriddenOnExit: false,
      factory: $LibraryRoute._fromState,
      routes: [
        GoRouteData.$route(
          path: 'platforms/:platformId',
          hasOverriddenOnExit: false,
          factory: $LibraryPlatformRoute._fromState,
        ),
        GoRouteData.$route(
          path: 'sources/:sourceId',
          hasOverriddenOnExit: false,
          factory: $LibrarySourceRoute._fromState,
        ),
        GoRouteData.$route(
          path: 'library-roots/:libraryRootId',
          hasOverriddenOnExit: false,
          factory: $LibraryRootScopeRoute._fromState,
        ),
      ],
    ),
    GoRouteData.$route(
      path: '/games/:gameId',
      hasOverriddenOnExit: false,
      factory: $GameDetailRoute._fromState,
    ),
    GoRouteData.$route(
      path: '/settings',
      hasOverriddenOnExit: false,
      factory: $SettingsRoute._fromState,
    ),
    GoRouteData.$route(
      path: '/sources',
      hasOverriddenOnExit: false,
      factory: $SourcesRoute._fromState,
      routes: [
        GoRouteData.$route(
          path: 'roots/:rootId',
          hasOverriddenOnExit: false,
          factory: $SourcesRootRoute._fromState,
        ),
      ],
    ),
    GoRouteData.$route(
      path: '/jobs',
      hasOverriddenOnExit: false,
      factory: $JobsRoute._fromState,
      routes: [
        GoRouteData.$route(
          path: ':jobRunId',
          hasOverriddenOnExit: false,
          factory: $JobsDetailRoute._fromState,
        ),
      ],
    ),
  ],
);

extension $ApplicationShellRouteExtension on ApplicationShellRoute {
  static ApplicationShellRoute _fromState(GoRouterState state) =>
      const ApplicationShellRoute();
}

mixin $LibraryRoute on GoRouteData {
  static LibraryRoute _fromState(GoRouterState state) => const LibraryRoute();

  @override
  String get location => GoRouteData.$location('/library');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $LibraryPlatformRoute on GoRouteData {
  static LibraryPlatformRoute _fromState(GoRouterState state) =>
      LibraryPlatformRoute(platformId: state.pathParameters['platformId']!);

  LibraryPlatformRoute get _self => this as LibraryPlatformRoute;

  @override
  String get location => GoRouteData.$location(
    '/library/platforms/${Uri.encodeComponent(_self.platformId)}',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $LibrarySourceRoute on GoRouteData {
  static LibrarySourceRoute _fromState(GoRouterState state) =>
      LibrarySourceRoute(sourceId: state.pathParameters['sourceId']!);

  LibrarySourceRoute get _self => this as LibrarySourceRoute;

  @override
  String get location => GoRouteData.$location(
    '/library/sources/${Uri.encodeComponent(_self.sourceId)}',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $LibraryRootScopeRoute on GoRouteData {
  static LibraryRootScopeRoute _fromState(GoRouterState state) =>
      LibraryRootScopeRoute(
        libraryRootId: state.pathParameters['libraryRootId']!,
      );

  LibraryRootScopeRoute get _self => this as LibraryRootScopeRoute;

  @override
  String get location => GoRouteData.$location(
    '/library/library-roots/${Uri.encodeComponent(_self.libraryRootId)}',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $GameDetailRoute on GoRouteData {
  static GameDetailRoute _fromState(GoRouterState state) =>
      GameDetailRoute(gameId: state.pathParameters['gameId']!);

  GameDetailRoute get _self => this as GameDetailRoute;

  @override
  String get location =>
      GoRouteData.$location('/games/${Uri.encodeComponent(_self.gameId)}');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $SettingsRoute on GoRouteData {
  static SettingsRoute _fromState(GoRouterState state) => const SettingsRoute();

  @override
  String get location => GoRouteData.$location('/settings');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $SourcesRoute on GoRouteData {
  static SourcesRoute _fromState(GoRouterState state) => const SourcesRoute();

  @override
  String get location => GoRouteData.$location('/sources');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $SourcesRootRoute on GoRouteData {
  static SourcesRootRoute _fromState(GoRouterState state) =>
      SourcesRootRoute(rootId: state.pathParameters['rootId']!);

  SourcesRootRoute get _self => this as SourcesRootRoute;

  @override
  String get location => GoRouteData.$location(
    '/sources/roots/${Uri.encodeComponent(_self.rootId)}',
  );

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $JobsRoute on GoRouteData {
  static JobsRoute _fromState(GoRouterState state) => const JobsRoute();

  @override
  String get location => GoRouteData.$location('/jobs');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}

mixin $JobsDetailRoute on GoRouteData {
  static JobsDetailRoute _fromState(GoRouterState state) =>
      JobsDetailRoute(jobRunId: state.pathParameters['jobRunId']!);

  JobsDetailRoute get _self => this as JobsDetailRoute;

  @override
  String get location =>
      GoRouteData.$location('/jobs/${Uri.encodeComponent(_self.jobRunId)}');

  @override
  void go(BuildContext context) => context.go(location);

  @override
  Future<T?> push<T>(BuildContext context) => context.push<T>(location);

  @override
  void pushReplacement(BuildContext context) =>
      context.pushReplacement(location);

  @override
  void replace(BuildContext context) => context.replace(location);
}
