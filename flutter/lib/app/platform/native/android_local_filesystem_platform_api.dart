import 'package:flutter/services.dart';

import '../application/local_filesystem_platform_api.dart';

/// Android MethodChannel adapter for `argus/local_filesystem_platform`.
///
/// Native discovery is intentionally separate from readiness and returns only
/// bounded, typed facts. Malformed replies and platform errors become a
/// bounded failure kind; native error text never reaches application copy.
final class MethodChannelAndroidLocalFilesystemPlatformApi
    implements LocalFilesystemPlatformApi {
  const MethodChannelAndroidLocalFilesystemPlatformApi({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('argus/local_filesystem_platform');

  final MethodChannel _channel;

  @override
  Future<List<PlatformMountedVolume>> readMountedVolumes() async {
    final List<Object?>? raw;
    try {
      raw = await _channel.invokeListMethod<Object?>('readMountedVolumes');
    } on PlatformException {
      throw const LocalFilesystemPlatformException(
        LocalFilesystemPlatformFailureKind.discoveryUnavailable,
      );
    } on MissingPluginException {
      throw const LocalFilesystemPlatformException(
        LocalFilesystemPlatformFailureKind.discoveryUnavailable,
      );
    }
    if (raw == null) {
      throw const LocalFilesystemPlatformException(
        LocalFilesystemPlatformFailureKind.discoveryUnavailable,
      );
    }
    return _parseSnapshot(raw);
  }

  List<PlatformMountedVolume> _parseSnapshot(List<Object?> raw) {
    if (raw.isEmpty || raw.length > maxPlatformMountedVolumes) {
      throw const LocalFilesystemPlatformException(
        LocalFilesystemPlatformFailureKind.malformedSnapshot,
      );
    }
    final ids = <String>{};
    final volumes = <PlatformMountedVolume>[];
    var primaryCount = 0;
    for (final item in raw) {
      if (item is! Map<Object?, Object?>) {
        throw const LocalFilesystemPlatformException(
          LocalFilesystemPlatformFailureKind.malformedSnapshot,
        );
      }
      final providerVolumeId = item['providerVolumeId'];
      final mountPath = item['transientMountPath'];
      final displayName = item['safeDisplayName'];
      final isPrimary = item['isPrimary'];
      final isRemovable = item['isRemovable'];
      if (providerVolumeId is! String ||
          providerVolumeId.trim().isEmpty ||
          mountPath is! String ||
          !mountPath.startsWith('/') ||
          displayName is! String ||
          displayName.trim().isEmpty ||
          isPrimary is! bool ||
          isRemovable is! bool ||
          !ids.add(providerVolumeId)) {
        throw const LocalFilesystemPlatformException(
          LocalFilesystemPlatformFailureKind.malformedSnapshot,
        );
      }
      if (isPrimary) primaryCount++;
      volumes.add(
        PlatformMountedVolume(
          providerVolumeId: providerVolumeId,
          transientMountPath: mountPath,
          safeDisplayName: displayName,
          isPrimary: isPrimary,
          isRemovable: isRemovable,
        ),
      );
    }
    if (primaryCount != 1) {
      throw const LocalFilesystemPlatformException(
        LocalFilesystemPlatformFailureKind.malformedSnapshot,
      );
    }
    return List<PlatformMountedVolume>.unmodifiable(volumes);
  }
}
