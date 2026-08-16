/// Pure-Dart platform facts and actions consumed by app composition.
///
/// This layer contains no Flutter widgets, generated bridge types, or
/// Android classes. Native OS mechanics stay behind [PlatformHostApi]
/// implementations owned by the `native` sub-layer.
library;

/// Terminal notification-authorization wire classification.
enum NotificationAuthorization { notRequired, promptRequired, granted, denied }

/// Bounded platform failure kinds; native error text never becomes UI copy.
enum PlatformReadinessFailureKind {
  snapshotUnavailable,
  settingsLaunchFailed,
  notificationRequestFailed,
}

/// One authoritative snapshot of the host platform's readiness facts.
final class PlatformHostSnapshot {
  const PlatformHostSnapshot({
    required this.allFilesAccessRequired,
    required this.allFilesAccessGranted,
    required this.notificationAuthorization,
    this.standardApplicationDataDirectory,
  });

  final bool allFilesAccessRequired;
  final bool allFilesAccessGranted;
  final NotificationAuthorization notificationAuthorization;
  final String? standardApplicationDataDirectory;
}

/// The narrow platform port used by readiness composition.
abstract interface class PlatformHostApi {
  Future<PlatformHostSnapshot> readSnapshot();

  Future<void> openAllFilesAccessSettings();

  Future<NotificationAuthorization> requestNotificationPermission();
}

/// Typed failure with a bounded kind; never carries native message text.
final class PlatformHostException implements Exception {
  const PlatformHostException(this.kind);

  final PlatformReadinessFailureKind kind;
}
