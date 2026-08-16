import 'dart:io';

import '../application/platform_host_api.dart';
import 'android_platform_host_api.dart';
import 'desktop_platform_host_api.dart';

/// Complete production platform composition chosen at app startup.
final class PlatformHostComposition {
  const PlatformHostComposition({
    required this.api,
    required this.requiresReadinessGate,
  });

  final PlatformHostApi api;
  final bool requiresReadinessGate;
}

/// Sole production OS-selection point for platform hosting.
PlatformHostComposition createPlatformHostComposition() {
  if (Platform.isAndroid) {
    return const PlatformHostComposition(
      api: MethodChannelAndroidPlatformHostApi(),
      requiresReadinessGate: true,
    );
  }
  return const PlatformHostComposition(
    api: DesktopPlatformHostApi(),
    requiresReadinessGate: false,
  );
}
