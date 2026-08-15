/// User-facing copy for the Jobs feature.
abstract final class JobsMessages {
  static const String title = 'Jobs';
  static const String emptyTitle = 'No jobs yet';
  static const String emptyBody =
      'Long-running Argus work, such as library scans, appears here.';
  static const String active = 'Active';
  static const String recent = 'Recent';
  static const String loadFailed = 'Jobs could not be loaded.';
  static const String retry = 'Retry';
  static const String loadMore = 'Load more';
  static const String jobNotFound = 'This job could not be found.';
  static const String backToJobs = 'Go to Jobs';
  static const String cancelJob = 'Cancel Job';
  static const String cancelConfirmationTitle = 'Cancel this job?';
  static const String cancelConfirmationBody =
      'Cancelling stops new work at the next safe checkpoint. '
      'Already saved results remain valid.';
  static const String cancelling = 'Cancelling…';
  static const String cancel = 'Cancel';
  static const String phase = 'Phase';
  static const String created = 'Created';
  static const String started = 'Started';
  static const String finished = 'Finished';
  static const String rootsRequested = 'Roots requested';
  static const String rootsAdmitted = 'Roots admitted';
  static const String rootsTerminal = 'Roots terminal';
  static const String entriesCommitted = 'Entries committed';
  static const String libraryScan = 'Library Scan';
}
