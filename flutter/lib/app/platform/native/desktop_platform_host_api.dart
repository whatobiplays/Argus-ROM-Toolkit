import '../application/platform_host_api.dart';

/// Inert host implementation used when no readiness gate is required.
final class DesktopPlatformHostApi implements PlatformHostApi {
  const DesktopPlatformHostApi();

  @override
  Future<PlatformHostSnapshot> readSnapshot() async =>
      const PlatformHostSnapshot(
        allFilesAccessRequired: false,
        allFilesAccessGranted: false,
        notificationAuthorization: NotificationAuthorization.notRequired,
        standardApplicationDataDirectory: null,
      );

  @override
  Future<void> openAllFilesAccessSettings() async {}

  @override
  Future<NotificationAuthorization> requestNotificationPermission() async =>
      NotificationAuthorization.notRequired;
}
