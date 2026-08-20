import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'presentation_seams.g.dart';

/// Presentation-only platform capability filter for startup recovery actions.
///
/// Backend recovery advertisement remains authoritative for actions the
/// runtime owns; this closed value lets app composition suppress a
/// platform-inapplicable action without mutating backend state.
final class StartupPresentationCapabilities {
  const StartupPresentationCapabilities({
    required this.diagnosticsExport,
    this.diagnosticsSharing = false,
    required this.openDataDirectory,
  });

  final bool diagnosticsExport;
  final bool diagnosticsSharing;
  final bool openDataDirectory;
}

/// Default capabilities preserve the existing desktop action set.
@Riverpod(keepAlive: true)
StartupPresentationCapabilities startupPresentationCapabilities(Ref ref) =>
    const StartupPresentationCapabilities(
      diagnosticsExport: true,
      openDataDirectory: true,
    );

/// Presentation-owned chooser for a diagnostic-export destination.
typedef DiagnosticsDestinationPicker =
    Future<String?> Function({required String suggestedName});

/// Provides the native save-location chooser used before export dispatch.
@Riverpod(keepAlive: true)
DiagnosticsDestinationPicker diagnosticsDestinationPicker(Ref ref) =>
    _pickDiagnosticsDestination;

Future<String?> _pickDiagnosticsDestination({
  required String suggestedName,
}) async {
  const typeGroup = XTypeGroup(
    label: 'ZIP archive',
    extensions: <String>['zip'],
  );
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const <XTypeGroup>[typeGroup],
  );
  return location?.path;
}

/// Presentation-owned application termination.
typedef AppTerminator = void Function();

/// Provides the desktop application terminator used by pre-ready Exit paths.
@Riverpod(keepAlive: true)
AppTerminator appTerminator(Ref ref) => _terminateDesktopApp;

void _terminateDesktopApp() {
  exit(0);
}
