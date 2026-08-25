// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_composition.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Optional Phase-003 metadata settings capability supplied by app
/// composition. Legacy and isolated test embeddings leave it unavailable.

@ProviderFor(settingsMetadataApi)
final settingsMetadataApiProvider = SettingsMetadataApiProvider._();

/// Optional Phase-003 metadata settings capability supplied by app
/// composition. Legacy and isolated test embeddings leave it unavailable.

final class SettingsMetadataApiProvider
    extends
        $FunctionalProvider<
          MetadataSettingsApi?,
          MetadataSettingsApi?,
          MetadataSettingsApi?
        >
    with $Provider<MetadataSettingsApi?> {
  /// Optional Phase-003 metadata settings capability supplied by app
  /// composition. Legacy and isolated test embeddings leave it unavailable.
  SettingsMetadataApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsMetadataApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsMetadataApiHash();

  @$internal
  @override
  $ProviderElement<MetadataSettingsApi?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MetadataSettingsApi? create(Ref ref) {
    return settingsMetadataApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MetadataSettingsApi? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MetadataSettingsApi?>(value),
    );
  }
}

String _$settingsMetadataApiHash() =>
    r'47047ba1db03b28fe89fa63a8461340ab9204574';

/// Optional Phase-003 provider readiness and write-only credential capability.

@ProviderFor(settingsMetadataProvidersApi)
final settingsMetadataProvidersApiProvider =
    SettingsMetadataProvidersApiProvider._();

/// Optional Phase-003 provider readiness and write-only credential capability.

final class SettingsMetadataProvidersApiProvider
    extends
        $FunctionalProvider<
          MetadataProvidersApi?,
          MetadataProvidersApi?,
          MetadataProvidersApi?
        >
    with $Provider<MetadataProvidersApi?> {
  /// Optional Phase-003 provider readiness and write-only credential capability.
  SettingsMetadataProvidersApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsMetadataProvidersApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsMetadataProvidersApiHash();

  @$internal
  @override
  $ProviderElement<MetadataProvidersApi?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MetadataProvidersApi? create(Ref ref) {
    return settingsMetadataProvidersApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MetadataProvidersApi? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MetadataProvidersApi?>(value),
    );
  }
}

String _$settingsMetadataProvidersApiHash() =>
    r'7f5107be31c5e61e7d126e8f35679f05f0d9e694';
