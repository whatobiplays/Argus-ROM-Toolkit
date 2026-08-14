import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'presentation_seams.g.dart';

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
