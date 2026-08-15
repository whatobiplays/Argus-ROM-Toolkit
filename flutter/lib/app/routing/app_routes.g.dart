// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_routes.dart';

// **************************************************************************
// GoRouterGenerator
// **************************************************************************

List<RouteBase> get $appRoutes => [$rootRoute, $applicationShellRoute];

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

RouteBase get $applicationShellRoute => ShellRouteData.$route(
  factory: $ApplicationShellRouteExtension._fromState,
  routes: [
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
  ],
);

extension $ApplicationShellRouteExtension on ApplicationShellRoute {
  static ApplicationShellRoute _fromState(GoRouterState state) =>
      const ApplicationShellRoute();
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
