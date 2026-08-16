import 'package:flutter/services.dart';

import '../application/platform_host_api.dart';

/// Android MethodChannel adapter for `argus/platform_readiness`.
///
/// Every wire field is validated and malformed replies become a bounded
/// [PlatformHostException]; native text never reaches UI or domain copy.
final class MethodChannelAndroidPlatformHostApi implements PlatformHostApi {
  const MethodChannelAndroidPlatformHostApi({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('argus/platform_readiness');

  final MethodChannel _channel;

  @override
  Future<PlatformHostSnapshot> readSnapshot() async {
    final Map<Object?, Object?>? raw;
    try {
      raw = await _channel.invokeMapMethod<Object?, Object?>('readSnapshot');
    } on PlatformException {
      throw const PlatformHostException(
        PlatformReadinessFailureKind.snapshotUnavailable,
      );
    }
    if (raw == null) {
      throw const PlatformHostException(
        PlatformReadinessFailureKind.snapshotUnavailable,
      );
    }
    return _parseSnapshot(raw);
  }

  @override
  Future<void> openAllFilesAccessSettings() async {
    try {
      await _channel.invokeMethod<void>('openAllFilesAccessSettings');
    } on PlatformException {
      throw const PlatformHostException(
        PlatformReadinessFailureKind.settingsLaunchFailed,
      );
    }
  }

  @override
  Future<NotificationAuthorization> requestNotificationPermission() async {
    final Object? value;
    try {
      value = await _channel.invokeMethod<Object?>(
        'requestNotificationPermission',
      );
    } on PlatformException {
      throw const PlatformHostException(
        PlatformReadinessFailureKind.notificationRequestFailed,
      );
    }
    return switch (value) {
      'notRequired' => NotificationAuthorization.notRequired,
      'promptRequired' => NotificationAuthorization.promptRequired,
      'granted' => NotificationAuthorization.granted,
      'denied' => NotificationAuthorization.denied,
      _ => throw const PlatformHostException(
        PlatformReadinessFailureKind.notificationRequestFailed,
      ),
    };
  }

  PlatformHostSnapshot _parseSnapshot(Map<Object?, Object?> raw) {
    final required = raw['allFilesAccessRequired'];
    final granted = raw['allFilesAccessGranted'];
    final authorization = raw['notificationAuthorization'];
    final standard = raw['standardApplicationDataDirectory'];
    if (required is! bool || granted is! bool || authorization is! String) {
      throw const PlatformHostException(
        PlatformReadinessFailureKind.snapshotUnavailable,
      );
    }
    final parsedAuthorization = switch (authorization) {
      'notRequired' => NotificationAuthorization.notRequired,
      'promptRequired' => NotificationAuthorization.promptRequired,
      'granted' => NotificationAuthorization.granted,
      'denied' => NotificationAuthorization.denied,
      _ => throw const PlatformHostException(
        PlatformReadinessFailureKind.snapshotUnavailable,
      ),
    };
    if (standard != null && standard is! String) {
      throw const PlatformHostException(
        PlatformReadinessFailureKind.snapshotUnavailable,
      );
    }
    return PlatformHostSnapshot(
      allFilesAccessRequired: required,
      allFilesAccessGranted: granted,
      notificationAuthorization: parsedAuthorization,
      standardApplicationDataDirectory: standard as String?,
    );
  }
}
