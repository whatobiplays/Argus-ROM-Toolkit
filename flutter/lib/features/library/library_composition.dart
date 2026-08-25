import 'package:argus/core/client/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'library_composition.g.dart';

/// Focused durable logical-library reads injected by app composition.
@Riverpod(keepAlive: true)
LibraryReads libraryApi(Ref ref) {
  throw StateError('libraryApiProvider must be supplied by app composition');
}

/// Focused configured-root reads used by the Library landing page.
@Riverpod(keepAlive: true)
SourcesApi librarySourcesApi(Ref ref) {
  throw StateError(
    'librarySourcesApiProvider must be supplied by app composition',
  );
}

/// Query-authoritative onboarding capability injected by app composition.
@Riverpod(keepAlive: true)
LibraryOnboardingApi libraryOnboardingApi(Ref ref) {
  throw StateError(
    'libraryOnboardingApiProvider must be supplied by app composition',
  );
}

/// Local metadata-preference capability injected by app composition.
@Riverpod(keepAlive: true)
MetadataSettingsApi libraryMetadataSettingsApi(Ref ref) {
  throw StateError(
    'libraryMetadataSettingsApiProvider must be supplied by app composition',
  );
}

/// Safe metadata-provider readiness and write-only credential capability used
/// by onboarding and provider settings.
@Riverpod(keepAlive: true)
MetadataProvidersApi libraryMetadataProvidersApi(Ref ref) {
  throw StateError(
    'libraryMetadataProvidersApiProvider must be supplied by app composition',
  );
}

/// Composed Library refresh admission capability injected by app composition.
@Riverpod(keepAlive: true)
LibraryRefreshApi libraryRefreshApi(Ref ref) {
  throw StateError(
    'libraryRefreshApiProvider must be supplied by app composition',
  );
}

/// Bounded Game detail and refresh capability injected by app composition.
@Riverpod(keepAlive: true)
GamesApi libraryGamesApi(Ref ref) {
  throw StateError(
    'libraryGamesApiProvider must be supplied by app composition',
  );
}
