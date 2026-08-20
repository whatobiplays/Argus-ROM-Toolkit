import 'package:argus/app/platform/application/platform_host_api.dart';
import 'package:argus/app/platform/application/platform_readiness_controller.dart';
import 'package:argus/app/platform/presentation/platform_readiness_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _GatePlatformHostApi api;

  setUp(() {
    api = _GatePlatformHostApi(
      const PlatformHostSnapshot(
        allFilesAccessRequired: true,
        allFilesAccessGranted: false,
        notificationAuthorization: NotificationAuthorization.promptRequired,
        standardApplicationDataDirectory:
            '/data/user/0/dev.argusromtoolkit.argus/files/argus',
      ),
    );
  });

  Future<void> pumpGate(WidgetTester tester) async {
    _CountingChild.buildCount = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [platformHostApiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: PlatformReadinessGate(child: _CountingChild()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('All files access step hides the child and opens settings', (
    tester,
  ) async {
    await pumpGate(tester);

    expect(find.text('Storage access required'), findsOneWidget);
    expect(find.text('Open Android settings'), findsOneWidget);
    expect(find.byType(_CountingChild), findsNothing);
    expect(_CountingChild.buildCount, 0);

    await tester.tap(find.text('Open Android settings'));
    await tester.pumpAndSettle();

    expect(api.settingsLaunches, 1);
    expect(find.byType(_CountingChild), findsNothing);
  });

  testWidgets('notification step hides the child and requests permission', (
    tester,
  ) async {
    api.snapshot = const PlatformHostSnapshot(
      allFilesAccessRequired: true,
      allFilesAccessGranted: true,
      notificationAuthorization: NotificationAuthorization.promptRequired,
      standardApplicationDataDirectory:
          '/data/user/0/dev.argusromtoolkit.argus/files/argus',
    );
    await pumpGate(tester);

    expect(find.text('Background job notifications'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(_CountingChild.buildCount, 0);

    api.requestedNotificationResult = NotificationAuthorization.granted;
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(api.notificationRequests, 1);
    expect(find.byType(_CountingChild), findsOneWidget);
    expect(_CountingChild.buildCount, 1);
  });

  testWidgets('snapshot failure shows bounded retry UI', (tester) async {
    api.snapshotError = StateError('secret native detail');
    await pumpGate(tester);

    expect(find.text('Platform check unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(_CountingChild.buildCount, 0);

    final readsBeforeRetry = api.snapshotReads;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(api.snapshotReads, greaterThan(readsBeforeRetry));
  });

  testWidgets('readiness actions remain reachable in a compact 2x window', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 360);
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;

    await pumpGate(tester);

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final actionFinder = find.text('Open Android settings');
    await tester.ensureVisible(actionFinder);
    await tester.pump();
    final action = tester.getRect(actionFinder);
    expect(action.bottom, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });

  testWidgets('resume triggers an authoritative refresh', (tester) async {
    await pumpGate(tester);
    final readsBeforeResume = api.snapshotReads;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(api.snapshotReads, greaterThan(readsBeforeResume));
  });

  testWidgets(
    'revocation on resume hides the child without backend replacement',
    (tester) async {
      api.snapshot = const PlatformHostSnapshot(
        allFilesAccessRequired: true,
        allFilesAccessGranted: true,
        notificationAuthorization: NotificationAuthorization.notRequired,
        standardApplicationDataDirectory:
            '/data/user/0/dev.argusromtoolkit.argus/files/argus',
      );
      await pumpGate(tester);
      expect(find.byType(_CountingChild), findsOneWidget);

      api.snapshot = const PlatformHostSnapshot(
        allFilesAccessRequired: true,
        allFilesAccessGranted: false,
        notificationAuthorization: NotificationAuthorization.notRequired,
        standardApplicationDataDirectory:
            '/data/user/0/dev.argusromtoolkit.argus/files/argus',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byType(_CountingChild), findsNothing);
      expect(find.text('Storage access required'), findsOneWidget);
    },
  );
}

final class _CountingChild extends StatelessWidget {
  const _CountingChild();

  static int buildCount = 0;

  @override
  Widget build(BuildContext context) {
    buildCount++;
    return const ColoredBox(color: Color(0xFF00FF00));
  }
}

final class _GatePlatformHostApi implements PlatformHostApi {
  _GatePlatformHostApi(this.snapshot);

  PlatformHostSnapshot snapshot;
  Object? snapshotError;
  NotificationAuthorization? requestedNotificationResult;
  int settingsLaunches = 0;
  int notificationRequests = 0;
  int snapshotReads = 0;

  @override
  Future<void> openAllFilesAccessSettings() async {
    settingsLaunches++;
  }

  @override
  Future<PlatformHostSnapshot> readSnapshot() async {
    snapshotReads++;
    final error = snapshotError;
    if (error != null) throw error;
    return snapshot;
  }

  @override
  Future<NotificationAuthorization> requestNotificationPermission() async {
    notificationRequests++;
    final result =
        requestedNotificationResult ?? NotificationAuthorization.promptRequired;
    if (result != NotificationAuthorization.promptRequired) {
      snapshot = PlatformHostSnapshot(
        allFilesAccessRequired: snapshot.allFilesAccessRequired,
        allFilesAccessGranted: snapshot.allFilesAccessGranted,
        notificationAuthorization: result,
        standardApplicationDataDirectory:
            snapshot.standardApplicationDataDirectory,
      );
    }
    return result;
  }
}
