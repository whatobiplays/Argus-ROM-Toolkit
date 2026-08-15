import 'package:argus/core/client/client.dart';

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
  static const String scanAll = 'Scan All';
  static const String addAndScan = 'Add & Scan';
  static const String addWithoutScanning = 'Add Without Scanning';
  static const String addAndScanExplainsNewFolder =
      'Argus will configure this folder and start indexing it immediately. '
      'Your files are never modified.';
  static const String addAndScanAdmissionFailed =
      'Folder added, but the scan could not start. You can scan it from the '
      'folder details.';
  static const String addAndScanUncertain = 'Scan not confirmed';
  static const String addAndScanUncertainBody =
      'Argus could not confirm whether indexing started. Refresh to check the '
      'authoritative job state before scanning again.';
  static const String reconcileNow = 'Refresh';
  static const String scanningUnavailableNote =
      'Scanning is not available yet. The folder will be configured and '
      'ready to scan in a future update.';
  static const String neverScanned = 'Never scanned';
  static const String scanningInProgress = 'Scanning in progress';
  static const String scan = 'Scan';
  static const String scanAgain = 'Scan Again';
  static const String viewJob = 'View Job';
  static String scanAllAdmitted(int admittedCount) =>
      'Scan started for $admittedCount folder${admittedCount == 1 ? '' : 's'}.';
  static String scanAllAdmittedWithExclusions(int admittedCount) =>
      'Scan started for $admittedCount folder${admittedCount == 1 ? '' : 's'}. '
      'Some folders were skipped — open the job for details.';
  static const String scanAllNothingEligible =
      'No folders could be scanned right now.';
  static String scanAllNothingEligibleReasons(List<String> reasons) =>
      'No folders could be scanned right now: ${reasons.join(', ')}.';
  static String scanAllExclusionLabel(
    LibraryScanAdmissionExclusion exclusion,
  ) => switch (exclusion.reason) {
    'already_scanning' => 'one folder is already being scanned',
    'invalid_configuration' => 'one folder has an invalid configuration',
    'no_longer_configured' => 'one folder is no longer configured',
    _ => 'one folder is not eligible',
  };
  static const String scanAllUncertain =
      'Scan not confirmed. Refreshing authoritative state — please wait '
      'before scanning again.';
  static const String rootHasActiveScan =
      'This folder is currently being scanned, so it cannot be removed yet. '
      'Open the job to follow or cancel the scan.';
  static String lastScanStatus(LibraryRootLastScanStatus status) =>
      switch (status) {
        LibraryRootLastScanStatus.complete => 'Last scan: complete',
        LibraryRootLastScanStatus.partial => 'Last scan: partial',
        LibraryRootLastScanStatus.unavailable => 'Last scan: unavailable',
        LibraryRootLastScanStatus.cancelled => 'Last scan: cancelled',
        LibraryRootLastScanStatus.failed => 'Last scan: failed',
        LibraryRootLastScanStatus.abandoned => 'Last scan: abandoned',
      };
  static const String availabilityLabel = 'Availability';
  static const String removeLibraryFolder = 'Remove Library Folder';
  static const String cancelScanAndRemove = 'Cancel Scan & Remove';
  static const String removeConfirmationTitle = 'Remove Library Folder?';
  static const String removeConfirmationBody =
      'Removes this folder and its indexed data from Argus. '
      'Files on disk are not changed.';
  static const String cancelAndRemoveConfirmationTitle =
      'Cancel Scan & Remove Library Folder?';
  static const String cancelAndRemoveConfirmationBody =
      'Stops the scan for this folder, then removes the folder and its '
      'indexed data from Argus. Files on disk are not changed.';
  static const String cancelAndRemovePending =
      'Stopping the scan, then removing this folder…';
  static const String cancelAndRemoveUncertain =
      'Cancellation could not be confirmed. Removal will continue only if '
      'the authoritative state shows the scan has stopped.';
  static String cancelAndRemoveStopsOtherRoots(int otherRootCount) =>
      'Cancelling this job also stops scanning for the other '
      '$otherRootCount folder${otherRootCount == 1 ? '' : 's'} in the same '
      'job.';
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

  static const String hierarchyLoading = 'Loading indexed entries…';
  static const String hierarchyLoadFailed =
      'Indexed entries could not be loaded.';
  static const String hierarchyRefreshFailed =
      'Could not refresh indexed entries. Showing the last confirmed state.';
  static const String hierarchyEmpty = 'No indexed entries yet.';
  static const String loadMore = 'Load more entries';
  static const String back = 'Back';
  static const String libraryRootLevel = 'Library root';
  static const String entryDetails = 'Entry details';
  static const String entryDetailsLoading = 'Loading entry details…';
  static const String entryDetailsFailed = 'Entry details could not be loaded.';

  static String entryKindLabel(SourceEntryKind kind) => switch (kind) {
    SourceEntryKind.directory => 'Folder',
    SourceEntryKind.file => 'File',
    SourceEntryKind.linkLike => 'Link',
    SourceEntryKind.unknown => 'Other',
  };

  static String entryClassificationLabel(
    SourceEntryClassification classification,
  ) => switch (classification) {
    SourceEntryClassification.container => 'Container',
    SourceEntryClassification.contentCandidate => 'Content candidate',
    SourceEntryClassification.supportingEntry => 'Supporting entry',
    SourceEntryClassification.ignored => 'Ignored',
    SourceEntryClassification.unknown => 'Unknown',
  };
}
