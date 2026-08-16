import 'package:argus/app/platform/application/platform_host_api.dart';
import 'package:argus/app/platform/application/platform_readiness_controller.dart';
import 'package:argus/app/platform/application/platform_readiness_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakePlatformHostApi api;

  setUp(() {
    api = _FakePlatformHostApi(
      const PlatformHostSnapshot(
        allFilesAccessRequired: true,
        allFilesAccessGranted: false,
        notificationAuthorization: NotificationAuthorization.promptRequired,
        standardApplicationDataDirectory:
            '/data/user/0/dev.argusromtoolkit.argus/files/argus',
      ),
    );
  });

  ProviderContainer container() => ProviderContainer(
    overrides: [platformHostApiProvider.overrideWithValue(api)],
  );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('denied All files access requires the All files step', () async {
    final scope = container();
    addTearDown(scope.dispose);

    scope.read(platformReadinessControllerProvider.notifier);
    await settle();

    expect(
      scope.read(platformReadinessControllerProvider),
      isA<PlatformReadinessRequiresAllFilesAccess>(),
    );
  });

  test('opening settings does not itself admit readiness', () async {
    final scope = container();
    addTearDown(scope.dispose);
    final notifier = scope.read(platformReadinessControllerProvider.notifier);
    await settle();

    await notifier.openAllFilesAccessSettings();
    await settle();

    expect(
      scope.read(platformReadinessControllerProvider),
      isA<PlatformReadinessRequiresAllFilesAccess>(),
    );
    expect(api.settingsLaunches, 1);
  });

  test('refresh after grant advances to the notification step', () async {
    final scope = container();
    addTearDown(scope.dispose);
    final notifier = scope.read(platformReadinessControllerProvider.notifier);
    await settle();

    api.snapshot = const PlatformHostSnapshot(
      allFilesAccessRequired: true,
      allFilesAccessGranted: true,
      notificationAuthorization: NotificationAuthorization.promptRequired,
      standardApplicationDataDirectory:
          '/data/user/0/dev.argusromtoolkit.argus/files/argus',
    );
    await notifier.refresh();

    expect(
      scope.read(platformReadinessControllerProvider),
      isA<PlatformReadinessRequiresNotificationPermission>(),
    );
  });

  test('granted notification response reaches Ready', () async {
    final scope = container();
    addTearDown(scope.dispose);
    final notifier = scope.read(platformReadinessControllerProvider.notifier);
    api.snapshot = const PlatformHostSnapshot(
      allFilesAccessRequired: true,
      allFilesAccessGranted: true,
      notificationAuthorization: NotificationAuthorization.promptRequired,
      standardApplicationDataDirectory:
          '/data/user/0/dev.argusromtoolkit.argus/files/argus',
    );
    api.requestedNotificationResult = NotificationAuthorization.granted;
    await settle();

    await notifier.requestNotificationPermission();
    await settle();

    final state = scope.read(platformReadinessControllerProvider);
    expect(state, isA<PlatformReadinessReady>());
    expect(
      (state as PlatformReadinessReady).notificationAuthorization,
      NotificationAuthorization.granted,
    );
  });

  test('denied notification response still reaches Ready', () async {
    final scope = container();
    addTearDown(scope.dispose);
    final notifier = scope.read(platformReadinessControllerProvider.notifier);
    api.snapshot = const PlatformHostSnapshot(
      allFilesAccessRequired: true,
      allFilesAccessGranted: true,
      notificationAuthorization: NotificationAuthorization.promptRequired,
      standardApplicationDataDirectory:
          '/data/user/0/dev.argusromtoolkit.argus/files/argus',
    );
    api.requestedNotificationResult = NotificationAuthorization.denied;
    await settle();

    await notifier.requestNotificationPermission();
    await settle();

    final state = scope.read(platformReadinessControllerProvider);
    expect(state, isA<PlatformReadinessReady>());
    expect(
      (state as PlatformReadinessReady).notificationAuthorization,
      NotificationAuthorization.denied,
    );
  });

  test('not-required notification reaches Ready', () async {
    api.snapshot = const PlatformHostSnapshot(
      allFilesAccessRequired: true,
      allFilesAccessGranted: true,
      notificationAuthorization: NotificationAuthorization.notRequired,
      standardApplicationDataDirectory:
          '/data/user/0/dev.argusromtoolkit.argus/files/argus',
    );
    final scope = container();
    addTearDown(scope.dispose);

    scope.read(platformReadinessControllerProvider.notifier);
    await settle();

    expect(
      scope.read(platformReadinessControllerProvider),
      isA<PlatformReadinessReady>(),
    );
  });

  test('snapshot failure becomes a bounded unavailable state', () async {
    api.snapshotError = PlatformException(
      code: 'READ_FAILED',
      message: 'secret native detail',
    );
    final scope = container();
    addTearDown(scope.dispose);

    scope.read(platformReadinessControllerProvider.notifier);
    await settle();

    final state = scope.read(platformReadinessControllerProvider);
    expect(state, isA<PlatformReadinessUnavailable>());
    expect(
      (state as PlatformReadinessUnavailable).failure,
      PlatformReadinessFailureKind.snapshotUnavailable,
    );
  });

  test('settings-launch failure keeps the bounded failure kind', () async {
    api.settingsError = PlatformException(
      code: 'SETTINGS_UNAVAILABLE',
      message: 'secret native detail',
    );
    final scope = container();
    addTearDown(scope.dispose);
    final notifier = scope.read(platformReadinessControllerProvider.notifier);
    await settle();

    await notifier.openAllFilesAccessSettings();

    final state = scope.read(platformReadinessControllerProvider);
    expect(state, isA<PlatformReadinessRequiresAllFilesAccess>());
    expect(
      (state as PlatformReadinessRequiresAllFilesAccess).failure,
      PlatformReadinessFailureKind.settingsLaunchFailed,
    );
  });

  test('notification-request failure keeps the bounded failure kind', () async {
    api.notificationError = PlatformException(
      code: 'NOTIFICATION_UNAVAILABLE',
      message: 'secret native detail',
    );
    api.snapshot = const PlatformHostSnapshot(
      allFilesAccessRequired: true,
      allFilesAccessGranted: true,
      notificationAuthorization: NotificationAuthorization.promptRequired,
      standardApplicationDataDirectory: null,
    );
    final scope = container();
    addTearDown(scope.dispose);
    final notifier = scope.read(platformReadinessControllerProvider.notifier);
    await settle();

    await notifier.requestNotificationPermission();

    final state = scope.read(platformReadinessControllerProvider);
    expect(state, isA<PlatformReadinessRequiresNotificationPermission>());
    expect(
      (state as PlatformReadinessRequiresNotificationPermission).failure,
      PlatformReadinessFailureKind.notificationRequestFailed,
    );
  });

  test(
    'Ready latches the runtime configuration for process lifetime',
    () async {
      api.snapshot = const PlatformHostSnapshot(
        allFilesAccessRequired: true,
        allFilesAccessGranted: true,
        notificationAuthorization: NotificationAuthorization.notRequired,
        standardApplicationDataDirectory:
            '/data/user/0/dev.argusromtoolkit.argus/files/argus',
      );
      final scope = container();
      addTearDown(scope.dispose);
      final notifier = scope.read(platformReadinessControllerProvider.notifier);
      await settle();

      final ready =
          scope.read(platformReadinessControllerProvider)
              as PlatformReadinessReady;
      expect(
        ready.runtimeConfiguration.standardApplicationDataDirectory,
        '/data/user/0/dev.argusromtoolkit.argus/files/argus',
      );

      // Revocation hides content but never changes the latched root.
      api.snapshot = const PlatformHostSnapshot(
        allFilesAccessRequired: true,
        allFilesAccessGranted: false,
        notificationAuthorization: NotificationAuthorization.notRequired,
        standardApplicationDataDirectory: '/replaced/root',
      );
      await notifier.refresh();
      expect(
        scope.read(platformReadinessControllerProvider),
        isA<PlatformReadinessRequiresAllFilesAccess>(),
      );
      expect(
        notifier.runtimeConfiguration!.standardApplicationDataDirectory,
        '/data/user/0/dev.argusromtoolkit.argus/files/argus',
      );

      // Regrant restores Ready with the original latched configuration.
      api.snapshot = const PlatformHostSnapshot(
        allFilesAccessRequired: true,
        allFilesAccessGranted: true,
        notificationAuthorization: NotificationAuthorization.notRequired,
        standardApplicationDataDirectory: '/replaced/root',
      );
      await notifier.refresh();
      final restored =
          scope.read(platformReadinessControllerProvider)
              as PlatformReadinessReady;
      expect(
        restored.runtimeConfiguration.standardApplicationDataDirectory,
        '/data/user/0/dev.argusromtoolkit.argus/files/argus',
      );
    },
  );
}

final class _FakePlatformHostApi implements PlatformHostApi {
  _FakePlatformHostApi(this.snapshot);

  PlatformHostSnapshot snapshot;
  Object? snapshotError;
  Object? settingsError;
  Object? notificationError;
  NotificationAuthorization? requestedNotificationResult;
  int settingsLaunches = 0;

  @override
  Future<void> openAllFilesAccessSettings() async {
    settingsLaunches++;
    final error = settingsError;
    if (error != null) throw error;
  }

  @override
  Future<PlatformHostSnapshot> readSnapshot() async {
    final error = snapshotError;
    if (error != null) throw error;
    return snapshot;
  }

  @override
  Future<NotificationAuthorization> requestNotificationPermission() async {
    final error = notificationError;
    if (error != null) throw error;
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
