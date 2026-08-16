import 'platform_host_api.dart';

/// Process-lifetime runtime configuration established by the first Ready
/// snapshot. Permission readiness may later regress, but an already running
/// Argus runtime must not be reconfigured or replaced because of it.
final class PlatformRuntimeConfiguration {
  const PlatformRuntimeConfiguration({this.standardApplicationDataDirectory});

  final String? standardApplicationDataDirectory;
}

/// Closed readiness vocabulary for the platform gate.
sealed class PlatformReadinessState {
  const PlatformReadinessState();
}

/// The first authoritative snapshot has not completed.
final class PlatformReadinessLoading extends PlatformReadinessState {
  const PlatformReadinessLoading();
}

/// Mandatory All files access is not live on the OS.
final class PlatformReadinessRequiresAllFilesAccess
    extends PlatformReadinessState {
  const PlatformReadinessRequiresAllFilesAccess({this.failure});

  final PlatformReadinessFailureKind? failure;
}

/// All files access is live and the optional notification prompt is pending.
final class PlatformReadinessRequiresNotificationPermission
    extends PlatformReadinessState {
  const PlatformReadinessRequiresNotificationPermission({this.failure});

  final PlatformReadinessFailureKind? failure;
}

/// Platform readiness is satisfied and the child application may be built.
final class PlatformReadinessReady extends PlatformReadinessState {
  const PlatformReadinessReady({
    required this.runtimeConfiguration,
    required this.notificationAuthorization,
  });

  final PlatformRuntimeConfiguration runtimeConfiguration;
  final NotificationAuthorization notificationAuthorization;
}

/// Readiness could not be established from the host.
final class PlatformReadinessUnavailable extends PlatformReadinessState {
  const PlatformReadinessUnavailable(this.failure);

  final PlatformReadinessFailureKind failure;
}

/// Classifies one authoritative host snapshot into the closed readiness
/// vocabulary.
PlatformReadinessState classifyPlatformReadiness(
  PlatformHostSnapshot snapshot,
) {
  if (snapshot.allFilesAccessRequired && !snapshot.allFilesAccessGranted) {
    return const PlatformReadinessRequiresAllFilesAccess();
  }
  if (snapshot.notificationAuthorization ==
      NotificationAuthorization.promptRequired) {
    return const PlatformReadinessRequiresNotificationPermission();
  }
  return PlatformReadinessReady(
    runtimeConfiguration: PlatformRuntimeConfiguration(
      standardApplicationDataDirectory:
          snapshot.standardApplicationDataDirectory,
    ),
    notificationAuthorization: snapshot.notificationAuthorization,
  );
}
