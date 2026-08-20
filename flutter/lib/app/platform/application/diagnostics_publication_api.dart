/// Platform publication capability for the completed backend-owned
/// diagnostics artifact.
library;

/// Native publication owns only the scoped share-sheet boundary. Rust remains
/// responsible for creating, sanitizing, completing, and validating the
/// diagnostic archive before this operation is called.
abstract interface class DiagnosticsPublicationApi {
  Future<void> publishCompletedStartupDiagnostics();
}

/// Bounded publication failure with no native text payload.
final class DiagnosticsPublicationException implements Exception {
  const DiagnosticsPublicationException(this.kind);

  final DiagnosticsPublicationFailureKind kind;
}

/// Stable publication failure vocabulary.
enum DiagnosticsPublicationFailureKind {
  artifactUnavailable,
  activityUnavailable,
  providerUnavailable,
  shareUnavailable,
}
