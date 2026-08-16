import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'platform_host_api.dart';
import 'platform_readiness_state.dart';

part 'platform_readiness_controller.g.dart';

/// DI seam for the platform host; app composition always supplies it.
@Riverpod(keepAlive: true)
PlatformHostApi platformHostApi(Ref ref) {
  throw StateError(
    'platformHostApiProvider must be supplied by app composition',
  );
}

/// Keep-alive authority for live platform readiness.
///
/// The first Ready snapshot latches the runtime configuration for the
/// process lifetime. Later permission revocation hides the application
/// through the readiness gate but never invalidates the client factory or
/// replaces an already initialized root runtime.
@Riverpod(keepAlive: true)
class PlatformReadinessController extends _$PlatformReadinessController {
  bool _refreshing = false;
  PlatformRuntimeConfiguration? _runtimeConfiguration;

  /// Process-lifetime runtime configuration from the first Ready snapshot.
  PlatformRuntimeConfiguration? get runtimeConfiguration =>
      _runtimeConfiguration;

  @override
  PlatformReadinessState build() {
    unawaited(refresh());
    return const PlatformReadinessLoading();
  }

  /// Re-reads the authoritative OS snapshot without showing a loading state.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final snapshot = await ref.read(platformHostApiProvider).readSnapshot();
      final classified = classifyPlatformReadiness(snapshot);
      if (classified case PlatformReadinessReady(
        :final runtimeConfiguration,
        :final notificationAuthorization,
      )) {
        _runtimeConfiguration ??= runtimeConfiguration;
        state = PlatformReadinessReady(
          runtimeConfiguration: _runtimeConfiguration!,
          notificationAuthorization: notificationAuthorization,
        );
      } else {
        state = classified;
      }
    } catch (_) {
      state = const PlatformReadinessUnavailable(
        PlatformReadinessFailureKind.snapshotUnavailable,
      );
    } finally {
      _refreshing = false;
    }
  }

  /// Launches the All files settings surface, then re-reads OS state.
  Future<void> openAllFilesAccessSettings() async {
    try {
      await ref.read(platformHostApiProvider).openAllFilesAccessSettings();
    } catch (_) {
      state = const PlatformReadinessRequiresAllFilesAccess(
        failure: PlatformReadinessFailureKind.settingsLaunchFailed,
      );
      return;
    }
    await refresh();
  }

  /// Requests the optional notification permission, then re-reads OS state.
  Future<void> requestNotificationPermission() async {
    try {
      final authorization = await ref
          .read(platformHostApiProvider)
          .requestNotificationPermission();
      // An interrupted/dismissed prompt is not a terminal response; stay on
      // the notification step until the user or OS resolves it.
      if (authorization == NotificationAuthorization.promptRequired) {
        return;
      }
    } catch (_) {
      state = const PlatformReadinessRequiresNotificationPermission(
        failure: PlatformReadinessFailureKind.notificationRequestFailed,
      );
      return;
    }
    await refresh();
  }
}
