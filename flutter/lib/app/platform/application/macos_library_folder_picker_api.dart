/// Framework-neutral macOS folder selection and durable authorization seam.
///
/// The authorization payload is intentionally an opaque byte sequence. Only
/// the macOS adapter and the LocalFilesystem provider may assign meaning to
/// it; presentation and application layers only transport it.
library;

/// Bounded failure vocabulary for the macOS native folder picker.
enum MacosLibraryFolderPickerFailureKind {
  nativeUnavailable,
  malformedResponse,
}

/// Typed picker failure that never carries native error text or objects.
final class MacosLibraryFolderPickerException implements Exception {
  const MacosLibraryFolderPickerException(this.kind);

  final MacosLibraryFolderPickerFailureKind kind;

  @override
  String toString() => 'MacosLibraryFolderPickerException($kind)';
}

/// One confirmed macOS folder plus its opaque durable authorization bytes.
final class MacosLibraryFolderSelection {
  MacosLibraryFolderSelection({
    required this.path,
    required List<int> authorization,
  }) : authorization = List<int>.unmodifiable(authorization);

  final String path;
  final List<int> authorization;

  @override
  String toString() => 'MacosLibraryFolderSelection(opaque authorization)';
}

/// Native folder-selection capability used by the macOS production picker.
abstract interface class MacosLibraryFolderPickerApi {
  Future<MacosLibraryFolderSelection?> pickLibraryFolder();
}
