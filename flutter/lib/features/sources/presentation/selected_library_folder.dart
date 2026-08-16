import 'package:argus/core/client/client.dart';

/// One user-confirmed library-folder selection plus safe backend presentation.
final class SelectedLibraryFolder {
  const SelectedLibraryFolder({
    required this.selection,
    required this.displayName,
    required this.safeLocationPresentation,
  });

  final LocalFilesystemRootSelection selection;
  final String displayName;
  final String safeLocationPresentation;
}
