import 'dart:io';

import '../application/local_filesystem_platform_api.dart';
import '../application/diagnostics_publication_api.dart';
import '../application/foreground_execution_host_api.dart';
import '../application/macos_library_folder_picker_api.dart';
import '../application/platform_host_api.dart';
import 'android_foreground_execution_host_api.dart';
import 'android_local_filesystem_platform_api.dart';
import 'android_diagnostics_publication_api.dart';
import 'android_platform_host_api.dart';
import 'desktop_platform_host_api.dart';
import 'macos_library_folder_picker_api.dart';

/// Complete production platform composition chosen at app startup.
final class PlatformHostComposition {
  const PlatformHostComposition({
    required this.api,
    required this.requiresReadinessGate,
    this.localFilesystemApi,
    this.foregroundExecutionHostApi,
    this.diagnosticsPublicationApi,
    this.macosLibraryFolderPickerApi,
  });

  final PlatformHostApi api;
  final bool requiresReadinessGate;
  final LocalFilesystemPlatformApi? localFilesystemApi;
  final ForegroundExecutionHostApi? foregroundExecutionHostApi;
  final DiagnosticsPublicationApi? diagnosticsPublicationApi;
  final MacosLibraryFolderPickerApi? macosLibraryFolderPickerApi;
}

/// Sole production OS-selection point for platform hosting.
PlatformHostComposition createPlatformHostComposition() {
  if (Platform.isAndroid) {
    return const PlatformHostComposition(
      api: MethodChannelAndroidPlatformHostApi(),
      requiresReadinessGate: true,
      localFilesystemApi: MethodChannelAndroidLocalFilesystemPlatformApi(),
      diagnosticsPublicationApi:
          MethodChannelAndroidDiagnosticsPublicationApi(),
      foregroundExecutionHostApi:
          MethodChannelAndroidForegroundExecutionHostApi(),
    );
  }
  if (Platform.isMacOS) {
    return const PlatformHostComposition(
      api: DesktopPlatformHostApi(),
      requiresReadinessGate: false,
      macosLibraryFolderPickerApi: MethodChannelMacosLibraryFolderPickerApi(),
    );
  }
  return const PlatformHostComposition(
    api: DesktopPlatformHostApi(),
    requiresReadinessGate: false,
  );
}
