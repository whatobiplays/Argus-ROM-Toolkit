import 'package:argus/app/platform/platform_host.dart';
import 'package:argus/core/client/client.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../sources_composition.dart';
import 'local_filesystem_browser.dart';
import 'selected_library_folder.dart';

part 'library_folder_picker.g.dart';

/// Presentation-owned native folder-picker seam.
///
/// Returns null when the user cancels. Platform errors are sanitized before
/// normal presentation; the feature never sees plugin-specific result types.
typedef LibraryFolderPicker =
    Future<SelectedLibraryFolder?> Function(
      BuildContext context,
      WidgetRef ref,
    );

/// Provides the native folder picker used by the add workflow.
@Riverpod(keepAlive: true)
LibraryFolderPicker libraryFolderPicker(Ref ref) {
  final capabilities = ref.watch(sourcesPresentationCapabilitiesProvider);
  if (capabilities.localFilesystemBrowser) {
    return _pickLibraryFolderWithArgusBrowser;
  }
  if (ref.watch(macosLibraryFolderPickerApiProvider) case final api?) {
    return (context, ref) =>
        _pickLibraryFolderWithMacosPicker(context, ref, api);
  }
  return _pickLibraryFolder;
}

Future<SelectedLibraryFolder?> _pickLibraryFolder(
  BuildContext context,
  WidgetRef ref,
) async {
  final path = await getDirectoryPath(confirmButtonText: 'Select Folder');
  if (path == null) return null;
  final displayName = path
      .split(RegExp(r'[/\\]'))
      .lastWhere((part) => part.isNotEmpty, orElse: () => path);
  return SelectedLibraryFolder(
    selection: LocalFilesystemRootSelection(path),
    displayName: displayName,
    safeLocationPresentation: path,
  );
}

Future<SelectedLibraryFolder?> _pickLibraryFolderWithMacosPicker(
  BuildContext context,
  WidgetRef ref,
  MacosLibraryFolderPickerApi api,
) async {
  final selected = await api.pickLibraryFolder();
  if (selected == null) return null;
  final displayName = selected.path
      .split(RegExp(r'[/\\]'))
      .lastWhere((part) => part.isNotEmpty, orElse: () => selected.path);
  return SelectedLibraryFolder(
    selection: LocalFilesystemRootSelection.macos(
      selected.path,
      selected.authorization,
    ),
    displayName: displayName,
    safeLocationPresentation: selected.path,
  );
}

Future<SelectedLibraryFolder?> _pickLibraryFolderWithArgusBrowser(
  BuildContext context,
  WidgetRef ref,
) => showDialog<SelectedLibraryFolder>(
  context: context,
  builder: (dialogContext) => Dialog(
    child: LocalFilesystemBrowser(
      onSelected: (selection) => Navigator.of(dialogContext).pop(selection),
      onCancel: () => Navigator.of(dialogContext).pop(),
    ),
  ),
);
