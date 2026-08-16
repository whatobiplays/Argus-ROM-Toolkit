// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'presentation_seams.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Default capabilities preserve the existing desktop action set.

@ProviderFor(startupPresentationCapabilities)
final startupPresentationCapabilitiesProvider =
    StartupPresentationCapabilitiesProvider._();

/// Default capabilities preserve the existing desktop action set.

final class StartupPresentationCapabilitiesProvider
    extends
        $FunctionalProvider<
          StartupPresentationCapabilities,
          StartupPresentationCapabilities,
          StartupPresentationCapabilities
        >
    with $Provider<StartupPresentationCapabilities> {
  /// Default capabilities preserve the existing desktop action set.
  StartupPresentationCapabilitiesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'startupPresentationCapabilitiesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$startupPresentationCapabilitiesHash();

  @$internal
  @override
  $ProviderElement<StartupPresentationCapabilities> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  StartupPresentationCapabilities create(Ref ref) {
    return startupPresentationCapabilities(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StartupPresentationCapabilities value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StartupPresentationCapabilities>(
        value,
      ),
    );
  }
}

String _$startupPresentationCapabilitiesHash() =>
    r'1c570d8828caca0593a17977ce48ac4457279376';

/// Provides the native save-location chooser used before export dispatch.

@ProviderFor(diagnosticsDestinationPicker)
final diagnosticsDestinationPickerProvider =
    DiagnosticsDestinationPickerProvider._();

/// Provides the native save-location chooser used before export dispatch.

final class DiagnosticsDestinationPickerProvider
    extends
        $FunctionalProvider<
          DiagnosticsDestinationPicker,
          DiagnosticsDestinationPicker,
          DiagnosticsDestinationPicker
        >
    with $Provider<DiagnosticsDestinationPicker> {
  /// Provides the native save-location chooser used before export dispatch.
  DiagnosticsDestinationPickerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'diagnosticsDestinationPickerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$diagnosticsDestinationPickerHash();

  @$internal
  @override
  $ProviderElement<DiagnosticsDestinationPicker> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DiagnosticsDestinationPicker create(Ref ref) {
    return diagnosticsDestinationPicker(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DiagnosticsDestinationPicker value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DiagnosticsDestinationPicker>(value),
    );
  }
}

String _$diagnosticsDestinationPickerHash() =>
    r'1b43e61e0fa921f198ff5d42f787fc84c65f18f3';

/// Provides the desktop application terminator used by pre-ready Exit paths.

@ProviderFor(appTerminator)
final appTerminatorProvider = AppTerminatorProvider._();

/// Provides the desktop application terminator used by pre-ready Exit paths.

final class AppTerminatorProvider
    extends $FunctionalProvider<AppTerminator, AppTerminator, AppTerminator>
    with $Provider<AppTerminator> {
  /// Provides the desktop application terminator used by pre-ready Exit paths.
  AppTerminatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appTerminatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appTerminatorHash();

  @$internal
  @override
  $ProviderElement<AppTerminator> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppTerminator create(Ref ref) {
    return appTerminator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppTerminator value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppTerminator>(value),
    );
  }
}

String _$appTerminatorHash() => r'f479b44e50a71292140d89c04bac73fd28f043fd';
