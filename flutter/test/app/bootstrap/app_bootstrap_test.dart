import 'package:argus/app/bootstrap/app_bootstrap.dart';
import 'package:argus/app/bootstrap/argus_app.dart';
import 'package:argus/app/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('bootstrap owns exactly one root ProviderScope', (tester) async {
    await tester.pumpWidget(const ArgusBootstrap());

    expect(find.byType(ProviderScope), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
  });

  testWidgets('ArgusApp accepts a test router through the provider seam', (
    tester,
  ) async {
    final testRouter = GoRouter(
      initialLocation: '/fixture',
      routes: <RouteBase>[
        GoRoute(
          path: '/fixture',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Test router page'))),
        ),
      ],
    );
    addTearDown(testRouter.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appRouterProvider.overrideWithValue(testRouter)],
        child: const ArgusApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test router page'), findsOneWidget);
  });
}
