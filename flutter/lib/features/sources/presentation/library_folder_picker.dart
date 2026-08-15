import 'package:argus/core/client/client.dart';
import 'package:file_selector/file_selector.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'library_folder_picker.g.dart';

/// Presentation-owned native folder-picker seam.
///
/// Returns null when the user cancels. Platform errors are sanitized before
/// normal presentation; the feature never sees plugin-specific result types.
typedef LibraryFolderPicker = Future<LocalFilesystemRootSelection?> Function();

/// Provides the native folder picker used by the add workflow.
@Riverpod(keepAlive: true)
LibraryFolderPicker libraryFolderPicker(Ref ref) => _pickLibraryFolder;

Future<LocalFilesystemRootSelection?> _pickLibraryFolder() async {
  final path = await getDirectoryPath(confirmButtonText: 'Select Folder');
  if (path == null) return null;
  return LocalFilesystemRootSelection(path);
}
