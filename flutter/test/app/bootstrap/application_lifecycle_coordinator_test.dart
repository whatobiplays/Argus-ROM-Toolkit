import 'dart:async';

import 'package:argus/app/platform/application/platform_host_api.dart';
import 'package:argus/app/platform/application/platform_readiness_controller.dart';
import 'package:argus/app/platform/application/platform_readiness_state.dart';
import 'package:argus/app/bootstrap/application_lifecycle_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('coalesces repeated desktop resumes into one demand', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [platformReadinessRequiredProvider.overrideWithValue(false)],
    );
    addTearDown(container.dispose);
    final demands = <ApplicationLifecycleReconciliationDemand>[];
    final subscription = container
        .read(applicationLifecycleReconciliationDemandProvider)
        .stream
        .listen(demands.add);
    addTearDown(subscription.cancel);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(demands, hasLength(1));
  });

  testWidgets('Android resumes refresh readiness before publishing demand', (
    tester,
  ) async {
    final api = _PlatformHostApi(
      const PlatformHostSnapshot(
        allFilesAccessRequired: true,
        allFilesAccessGranted: false,
        notificationAuthorization: NotificationAuthorization.notRequired,
        standardApplicationDataDirectory: '/data/argus',
      ),
    );
    final container = ProviderContainer(
      overrides: [
        platformReadinessRequiredProvider.overrideWithValue(true),
        platformHostApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    container.read(platformReadinessControllerProvider.notifier);
    await tester.pump();
    expect(
      container.read(platformReadinessControllerProvider),
      isA<PlatformReadinessRequiresAllFilesAccess>(),
    );

    final demands = <ApplicationLifecycleReconciliationDemand>[];
    final subscription = container
        .read(applicationLifecycleReconciliationDemandProvider)
        .stream
        .listen(demands.add);
    addTearDown(subscription.cancel);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(demands, isEmpty);

    api.snapshot = const PlatformHostSnapshot(
      allFilesAccessRequired: true,
      allFilesAccessGranted: true,
      notificationAuthorization: NotificationAuthorization.notRequired,
      standardApplicationDataDirectory: '/data/argus',
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(demands, hasLength(1));
    expect(
      container.read(platformReadinessControllerProvider),
      isA<PlatformReadinessReady>(),
    );
    expect(api.reads, greaterThanOrEqualTo(3));
  });

  testWidgets('resume waits for an in-flight startup readiness read', (
    tester,
  ) async {
    final api = _PlatformHostApi(
      const PlatformHostSnapshot(
        allFilesAccessRequired: true,
        allFilesAccessGranted: false,
        notificationAuthorization: NotificationAuthorization.notRequired,
        standardApplicationDataDirectory: '/data/argus',
      ),
    );
    final startupRead = Completer<void>();
    api.readGates.add(startupRead);
    final container = ProviderContainer(
      overrides: [
        platformReadinessRequiredProvider.overrideWithValue(true),
        platformHostApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    container.read(platformReadinessControllerProvider.notifier);
    await tester.pump();

    final demands = <ApplicationLifecycleReconciliationDemand>[];
    final subscription = container
        .read(applicationLifecycleReconciliationDemandProvider)
        .stream
        .listen(demands.add);
    addTearDown(subscription.cancel);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(demands, isEmpty);
    api.snapshot = const PlatformHostSnapshot(
      allFilesAccessRequired: true,
      allFilesAccessGranted: true,
      notificationAuthorization: NotificationAuthorization.notRequired,
      standardApplicationDataDirectory: '/data/argus',
    );
    startupRead.complete();
    await tester.pump();
    await tester.pump();

    expect(demands, hasLength(1));
    expect(
      container.read(platformReadinessControllerProvider),
      isA<PlatformReadinessReady>(),
    );
  });

  testWidgets('queues a resume received during readiness reconciliation', (
    tester,
  ) async {
    final api = _PlatformHostApi(
      const PlatformHostSnapshot(
        allFilesAccessRequired: true,
        allFilesAccessGranted: true,
        notificationAuthorization: NotificationAuthorization.notRequired,
        standardApplicationDataDirectory: '/data/argus',
      ),
    );
    final container = ProviderContainer(
      overrides: [
        platformReadinessRequiredProvider.overrideWithValue(true),
        platformHostApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    container.read(platformReadinessControllerProvider.notifier);
    await tester.pump();
    await tester.pump();

    final demands = <ApplicationLifecycleReconciliationDemand>[];
    final subscription = container
        .read(applicationLifecycleReconciliationDemandProvider)
        .stream
        .listen(demands.add);
    addTearDown(subscription.cancel);

    final firstReconcile = Completer<void>();
    final queuedReconcile = Completer<void>();
    api.snapshot = const PlatformHostSnapshot(
      allFilesAccessRequired: true,
      allFilesAccessGranted: false,
      notificationAuthorization: NotificationAuthorization.notRequired,
      standardApplicationDataDirectory: '/data/argus',
    );
    api.readGates.add(firstReconcile);
    api.readGates.add(queuedReconcile);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(demands, isEmpty);
    firstReconcile.complete();
    await tester.pump();
    await tester.pump();
    expect(api.reads, greaterThanOrEqualTo(3));
    expect(demands, isEmpty);

    api.snapshot = const PlatformHostSnapshot(
      allFilesAccessRequired: true,
      allFilesAccessGranted: true,
      notificationAuthorization: NotificationAuthorization.notRequired,
      standardApplicationDataDirectory: '/data/argus',
    );
    queuedReconcile.complete();
    await tester.pump();
    await tester.pump();

    expect(demands, hasLength(1));
  });
}

final class _PlatformHostApi implements PlatformHostApi {
  _PlatformHostApi(this.snapshot);

  PlatformHostSnapshot snapshot;
  int reads = 0;
  final readGates = <Completer<void>>[];

  @override
  Future<void> openAllFilesAccessSettings() async {}

  @override
  Future<PlatformHostSnapshot> readSnapshot() async {
    reads++;
    if (readGates.isNotEmpty) {
      await readGates.removeAt(0).future;
    }
    return snapshot;
  }

  @override
  Future<NotificationAuthorization> requestNotificationPermission() async =>
      NotificationAuthorization.notRequired;
}
