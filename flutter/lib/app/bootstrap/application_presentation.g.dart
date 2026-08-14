// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'application_presentation.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Projects backend readiness plus appearance authority onto shell admission.

@ProviderFor(applicationPresentationReadiness)
final applicationPresentationReadinessProvider =
    ApplicationPresentationReadinessProvider._();

/// Projects backend readiness plus appearance authority onto shell admission.

final class ApplicationPresentationReadinessProvider
    extends
        $FunctionalProvider<
          ApplicationPresentationReadiness,
          ApplicationPresentationReadiness,
          ApplicationPresentationReadiness
        >
    with $Provider<ApplicationPresentationReadiness> {
  /// Projects backend readiness plus appearance authority onto shell admission.
  ApplicationPresentationReadinessProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'applicationPresentationReadinessProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$applicationPresentationReadinessHash();

  @$internal
  @override
  $ProviderElement<ApplicationPresentationReadiness> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ApplicationPresentationReadiness create(Ref ref) {
    return applicationPresentationReadiness(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ApplicationPresentationReadiness value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ApplicationPresentationReadiness>(
        value,
      ),
    );
  }
}

String _$applicationPresentationReadinessHash() =>
    r'1c1b1cb812bdc4a78f24627ae37b4c7675abdf69';

/// Projection of confirmed appearance authority onto the root theme mode.
///
/// Owns no mutable theme state; null means no confirmed authority exists yet
/// and the bootstrap presentation fallback remains in effect behind the gate.

@ProviderFor(rootThemeMode)
final rootThemeModeProvider = RootThemeModeProvider._();

/// Projection of confirmed appearance authority onto the root theme mode.
///
/// Owns no mutable theme state; null means no confirmed authority exists yet
/// and the bootstrap presentation fallback remains in effect behind the gate.

final class RootThemeModeProvider
    extends
        $FunctionalProvider<
          material.ThemeMode?,
          material.ThemeMode?,
          material.ThemeMode?
        >
    with $Provider<material.ThemeMode?> {
  /// Projection of confirmed appearance authority onto the root theme mode.
  ///
  /// Owns no mutable theme state; null means no confirmed authority exists yet
  /// and the bootstrap presentation fallback remains in effect behind the gate.
  RootThemeModeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'rootThemeModeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$rootThemeModeHash();

  @$internal
  @override
  $ProviderElement<material.ThemeMode?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  material.ThemeMode? create(Ref ref) {
    return rootThemeMode(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(material.ThemeMode? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<material.ThemeMode?>(value),
    );
  }
}

String _$rootThemeModeHash() => r'1e791302d7768b63e74b0e9c085ded2968b0857c';
