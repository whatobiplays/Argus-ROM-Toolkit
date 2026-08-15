/// User-facing copy for the Sources feature.
///
/// Copy deliberately avoids provider, persistence, and scan terminology and
/// never exposes locators, identities, or raw native failures.
abstract final class SourcesMessages {
  static const String emptyTitle = 'No library folders yet';
  static const String emptyBody =
      'Library Folders are folders Argus indexes as configured sources. '
      'Adding one lets Argus read it later — it does not modify your files.';
  static const String addLibraryFolder = 'Add Library Folder';
  static const String scanningUnavailableNote =
      'Scanning is not available yet. The folder will be configured and '
      'ready to scan in a future update.';
  static const String neverScanned = 'Never scanned';
  static const String availabilityLabel = 'Availability';
  static const String removeLibraryFolder = 'Remove Library Folder';
  static const String removeConfirmationTitle = 'Remove Library Folder?';
  static const String removeConfirmationBody =
      'Removes this folder and its indexed data from Argus. '
      'Files on disk are not changed.';
  static const String remove = 'Remove';
  static const String cancel = 'Cancel';
  static const String openExistingFolder = 'Open existing folder';
  static const String folderAlreadyConfigured =
      'This folder is already configured as a Library Folder.';
  static const String folderOverlapsExisting =
      'This folder overlaps an existing configured Library Folder.';
  static const String pickerFailed =
      'The folder picker could not be opened. Please try again.';
  static const String addFailed =
      'The folder could not be added. Please try again.';
  static const String addAmbiguous =
      'Argus could not confirm whether the folder was added. '
      'The configured folders below are authoritative.';
  static const String removeFailed =
      'The folder could not be removed. Please try again.';
  static const String removeAmbiguous =
      'Argus could not confirm whether the folder was removed. '
      'The current configuration below is authoritative.';
  static const String refreshFailed =
      'Could not refresh library folders. Showing the last confirmed state.';
  static const String loadFailed = 'Library folders could not be loaded.';
  static const String retry = 'Retry';
  static const String backToSources = 'Go to Sources';
  static const String invalidLocation =
      'This location is not a valid library-folder location.';
}
