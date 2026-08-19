import 'dart:io';

import '../application/local_filesystem_platform_api.dart';
import '../application/foreground_execution_host_api.dart';
import '../application/platform_host_api.dart';
import 'android_foreground_execution_host_api.dart';
import 'android_local_filesystem_platform_api.dart';
import 'android_platform_host_api.dart';
import 'desktop_platform_host_api.dart';

/// Complete production platform composition chosen at app startup.
final class PlatformHostComposition {
  const PlatformHostComposition({
    required this.api,
    required this.requiresReadinessGate,
    this.localFilesystemApi,
    this.foregroundExecutionHostApi,
  });

  final PlatformHostApi api;
  final bool requiresReadinessGate;
  final LocalFilesystemPlatformApi? localFilesystemApi;
  final ForegroundExecutionHostApi? foregroundExecutionHostApi;
}

/// Sole production OS-selection point for platform hosting.
PlatformHostComposition createPlatformHostComposition() {
  if (Platform.isAndroid) {
    return const PlatformHostComposition(
      api: MethodChannelAndroidPlatformHostApi(),
      requiresReadinessGate: true,
      localFilesystemApi: MethodChannelAndroidLocalFilesystemPlatformApi(),
      foregroundExecutionHostApi:
          MethodChannelAndroidForegroundExecutionHostApi(),
    );
  }
  return const PlatformHostComposition(
    api: DesktopPlatformHostApi(),
    requiresReadinessGate: false,
  );
}
