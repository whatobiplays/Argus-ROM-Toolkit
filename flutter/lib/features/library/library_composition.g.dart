// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_composition.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Focused durable logical-library reads injected by app composition.

@ProviderFor(libraryApi)
final libraryApiProvider = LibraryApiProvider._();

/// Focused durable logical-library reads injected by app composition.

final class LibraryApiProvider
    extends $FunctionalProvider<LibraryReads, LibraryReads, LibraryReads>
    with $Provider<LibraryReads> {
  /// Focused durable logical-library reads injected by app composition.
  LibraryApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryApiHash();

  @$internal
  @override
  $ProviderElement<LibraryReads> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LibraryReads create(Ref ref) {
    return libraryApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LibraryReads value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LibraryReads>(value),
    );
  }
}

String _$libraryApiHash() => r'c6a6d30a366780eed3a1e3f013970c8c6b368983';

/// Focused configured-root reads used by the Library landing page.

@ProviderFor(librarySourcesApi)
final librarySourcesApiProvider = LibrarySourcesApiProvider._();

/// Focused configured-root reads used by the Library landing page.

final class LibrarySourcesApiProvider
    extends $FunctionalProvider<SourcesApi, SourcesApi, SourcesApi>
    with $Provider<SourcesApi> {
  /// Focused configured-root reads used by the Library landing page.
  LibrarySourcesApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'librarySourcesApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$librarySourcesApiHash();

  @$internal
  @override
  $ProviderElement<SourcesApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SourcesApi create(Ref ref) {
    return librarySourcesApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SourcesApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SourcesApi>(value),
    );
  }
}

String _$librarySourcesApiHash() => r'389bb3a0521c241b6c2917cf4ac1fca775a0dabb';

/// Query-authoritative onboarding capability injected by app composition.

@ProviderFor(libraryOnboardingApi)
final libraryOnboardingApiProvider = LibraryOnboardingApiProvider._();

/// Query-authoritative onboarding capability injected by app composition.

final class LibraryOnboardingApiProvider
    extends
        $FunctionalProvider<
          LibraryOnboardingApi,
          LibraryOnboardingApi,
          LibraryOnboardingApi
        >
    with $Provider<LibraryOnboardingApi> {
  /// Query-authoritative onboarding capability injected by app composition.
  LibraryOnboardingApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryOnboardingApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryOnboardingApiHash();

  @$internal
  @override
  $ProviderElement<LibraryOnboardingApi> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LibraryOnboardingApi create(Ref ref) {
    return libraryOnboardingApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LibraryOnboardingApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LibraryOnboardingApi>(value),
    );
  }
}

String _$libraryOnboardingApiHash() =>
    r'1ad5ca56fee34cfb93749d478bb359ef561a1a31';

/// Local metadata-preference capability injected by app composition.

@ProviderFor(libraryMetadataSettingsApi)
final libraryMetadataSettingsApiProvider =
    LibraryMetadataSettingsApiProvider._();

/// Local metadata-preference capability injected by app composition.

final class LibraryMetadataSettingsApiProvider
    extends
        $FunctionalProvider<
          MetadataSettingsApi,
          MetadataSettingsApi,
          MetadataSettingsApi
        >
    with $Provider<MetadataSettingsApi> {
  /// Local metadata-preference capability injected by app composition.
  LibraryMetadataSettingsApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryMetadataSettingsApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryMetadataSettingsApiHash();

  @$internal
  @override
  $ProviderElement<MetadataSettingsApi> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MetadataSettingsApi create(Ref ref) {
    return libraryMetadataSettingsApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MetadataSettingsApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MetadataSettingsApi>(value),
    );
  }
}

String _$libraryMetadataSettingsApiHash() =>
    r'aa8385914770332e01eab4b0fcdd325be52282dc';

/// Safe metadata-provider readiness and write-only credential capability used
/// by onboarding and provider settings.

@ProviderFor(libraryMetadataProvidersApi)
final libraryMetadataProvidersApiProvider =
    LibraryMetadataProvidersApiProvider._();

/// Safe metadata-provider readiness and write-only credential capability used
/// by onboarding and provider settings.

final class LibraryMetadataProvidersApiProvider
    extends
        $FunctionalProvider<
          MetadataProvidersApi,
          MetadataProvidersApi,
          MetadataProvidersApi
        >
    with $Provider<MetadataProvidersApi> {
  /// Safe metadata-provider readiness and write-only credential capability used
  /// by onboarding and provider settings.
  LibraryMetadataProvidersApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryMetadataProvidersApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryMetadataProvidersApiHash();

  @$internal
  @override
  $ProviderElement<MetadataProvidersApi> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MetadataProvidersApi create(Ref ref) {
    return libraryMetadataProvidersApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MetadataProvidersApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MetadataProvidersApi>(value),
    );
  }
}

String _$libraryMetadataProvidersApiHash() =>
    r'1741fa1f7d9af146db1b1b84d49da0f19d34813e';

/// Composed Library refresh admission capability injected by app composition.

@ProviderFor(libraryRefreshApi)
final libraryRefreshApiProvider = LibraryRefreshApiProvider._();

/// Composed Library refresh admission capability injected by app composition.

final class LibraryRefreshApiProvider
    extends
        $FunctionalProvider<
          LibraryRefreshApi,
          LibraryRefreshApi,
          LibraryRefreshApi
        >
    with $Provider<LibraryRefreshApi> {
  /// Composed Library refresh admission capability injected by app composition.
  LibraryRefreshApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryRefreshApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryRefreshApiHash();

  @$internal
  @override
  $ProviderElement<LibraryRefreshApi> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LibraryRefreshApi create(Ref ref) {
    return libraryRefreshApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LibraryRefreshApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LibraryRefreshApi>(value),
    );
  }
}

String _$libraryRefreshApiHash() => r'bf4b41fdbdc6ecb51c16ee6068f63101ee10ffb6';

/// Bounded Game detail and refresh capability injected by app composition.

@ProviderFor(libraryGamesApi)
final libraryGamesApiProvider = LibraryGamesApiProvider._();

/// Bounded Game detail and refresh capability injected by app composition.

final class LibraryGamesApiProvider
    extends $FunctionalProvider<GamesApi, GamesApi, GamesApi>
    with $Provider<GamesApi> {
  /// Bounded Game detail and refresh capability injected by app composition.
  LibraryGamesApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryGamesApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryGamesApiHash();

  @$internal
  @override
  $ProviderElement<GamesApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GamesApi create(Ref ref) {
    return libraryGamesApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GamesApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GamesApi>(value),
    );
  }
}

String _$libraryGamesApiHash() => r'07f91539af3b4c746e46e22d20c02de310d9c93a';
