import 'package:argus/core/client/client.dart';

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
  static const String requestedFolders = 'Requested folders';
  static const String excluded = 'Excluded';
  static const String entriesObserved = 'Entries observed';
  static const String entriesCommitted = 'Entries committed';
  static const String issues = 'Issues';
  static const String libraryScan = 'Library Scan';
  static const String libraryRefresh = 'Library Refresh';
  static const String gameRefresh = 'Game Refresh';
  static const String libraryResolutionRefresh = 'Metadata Resolution';
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

  /// Heading for the bounded explanation attached to a partial refresh.
  static const String refreshIssuesTitle = 'Why this finished with issues';
  static const String refreshIssuesShowAll = 'Show all issue details';
  static const String refreshIssuesShowLess = 'Show fewer issue details';
  static const int refreshIssuesVisible = 5;

  /// Returns the broad category shown for one durable refresh issue.
  static String refreshIssueKindLabel(RefreshIssueKind kind) => switch (kind) {
    RefreshIssueKind.matching => 'Content matching',
    RefreshIssueKind.metadata => 'Metadata',
    RefreshIssueKind.artworkDiscovery => 'Artwork discovery',
    RefreshIssueKind.artworkDownload => 'Artwork download',
    RefreshIssueKind.assetStore => 'Artwork storage',
    RefreshIssueKind.content => 'Local content',
    RefreshIssueKind.scope => 'Requested folders',
  };

  /// Returns the product-facing reason for one durable refresh issue.
  ///
  /// The switch is exhaustive over the closed vocabulary, so a new backend
  /// reason cannot ship without product copy.
  static String refreshIssueReasonLabel(RefreshIssueReason reason) =>
      switch (reason) {
        RefreshIssueReason.providerAuthenticationFailed =>
          'provider credentials were rejected',
        RefreshIssueReason.providerAuthorizationFailed =>
          'the provider rejected the request authorization',
        RefreshIssueReason.providerMisconfigured =>
          'the provider configuration is invalid',
        RefreshIssueReason.providerRateLimited =>
          'the provider asked to slow down',
        RefreshIssueReason.providerTimeout => 'the provider request timed out',
        RefreshIssueReason.providerUnavailable =>
          'the metadata provider was unavailable',
        RefreshIssueReason.providerInvalidResponse =>
          'the provider returned an unusable response',
        RefreshIssueReason.providerUnsupportedCapability =>
          'the provider does not support this capability',
        RefreshIssueReason.artworkAssetTooLarge =>
          'downloaded artwork was too large',
        RefreshIssueReason.artworkAssetInvalidImage =>
          'downloaded artwork was not a usable image',
        RefreshIssueReason.artworkAssetDimensionsTooLarge =>
          'downloaded artwork dimensions were too large',
        RefreshIssueReason.artworkAssetStoreUnavailable =>
          'local artwork storage was unavailable',
        RefreshIssueReason.contentUnavailable =>
          'admitted content could not be read',
        RefreshIssueReason.contentMalformedOrUnsupported =>
          'content was malformed or unsupported',
        RefreshIssueReason.contentEncryptedUnsupported =>
          'content needs a key that is not available',
        RefreshIssueReason.contentDependencyMissing =>
          'content is missing a required file',
        RefreshIssueReason.contentResourceLimitExceeded =>
          'content exceeded a processing limit',
        RefreshIssueReason.contentChangedDuringRefresh =>
          'content changed while it was being read',
        RefreshIssueReason.contentIdentityUnsupported =>
          'the content identity is not recognized',
        RefreshIssueReason.contentIdentificationFailed =>
          'content could not be identified',
        RefreshIssueReason.contentGroupingFailed =>
          'committed grouping could not be applied',
        RefreshIssueReason.contentRefreshFailed =>
          'a local content refresh step failed',
        RefreshIssueReason.scopeRootNotAdmitted =>
          'a requested folder was excluded from this refresh',
        RefreshIssueReason.scopeRootScanIncomplete =>
          'a folder scan reached only partial coverage',
        RefreshIssueReason.scopeRootScanFailed => 'a folder scan failed',
      };

  /// Returns the bounded product-facing line for one durable refresh issue
  /// fact, naming the provider and affected count only when they apply.
  static String refreshIssueFactLabel(RefreshIssueFact fact) {
    final kind = refreshIssueKindLabel(fact.kind);
    final reason = refreshIssueReasonLabel(fact.reason);
    final provider = _refreshIssueProviderLabel(fact.providerId);
    final providerSuffix = provider == null ? '' : ' ($provider)';
    final occurrences = fact.occurrences > 1
        ? ' (${fact.occurrences} affected)'
        : '';
    return '$kind: $reason$providerSuffix$occurrences';
  }

  /// Maps one durable provider identity into product copy.
  ///
  /// An unrecognized value is omitted rather than echoed, so no backend
  /// identifier becomes user-facing text.
  static String? _refreshIssueProviderLabel(String? providerId) =>
      switch (providerId) {
        'playmatch' => 'Playmatch',
        'gametdb' => 'GameTDB',
        'steamgriddb' => 'SteamGridDB',
        _ => null,
      };

  static String exclusionLabel(String reason) => switch (reason) {
    'already_scanning' => 'Already being scanned',
    'no_longer_configured' => 'No longer configured',
    'invalid_configuration' => 'Invalid configuration',
    _ => 'Not eligible',
  };
}
