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
  static const String entriesObserved = 'Entries observed';
  static const String entriesCommitted = 'Entries committed';
  static const String issues = 'Issues';
  static const String libraryScan = 'Library Scan';
  static const String retryJob = 'Retry';
  static const String retryConfirmationTitle = 'Retry this job?';
  static const String retryConfirmationBody =
      'Retry creates a new execution attempt with its own identity. '
      'The historical run remains unchanged.';
  static const String retrying = 'Retrying…';
  static const String retryUncertain =
      'Retry could not be confirmed. Refreshing authoritative state.';
  static const String retrySourceRunNotTerminal =
      'This execution is still running, so it cannot be retried yet.';
  static const String retryOperationNotRetryable =
      'This execution is not retryable. Cleanly completed scans use '
      'Scan Again from the folder instead.';
  static const String retryNoEligibleTargets =
      'No original folder remains eligible, so no new scan was created.';
  static const String retriedFrom = 'Retried from';
  static const String retriedAs = 'Retried as';
}
