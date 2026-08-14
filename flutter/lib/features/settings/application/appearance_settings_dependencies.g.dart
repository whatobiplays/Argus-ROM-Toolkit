// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'appearance_settings_dependencies.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Focused appearance-settings capability injected by app composition.
///
/// This is a dependency-injection seam only: it contains no root-client
/// construction, retries, caching, or workflow.

@ProviderFor(appearanceSettingsApi)
final appearanceSettingsApiProvider = AppearanceSettingsApiProvider._();

/// Focused appearance-settings capability injected by app composition.
///
/// This is a dependency-injection seam only: it contains no root-client
/// construction, retries, caching, or workflow.

final class AppearanceSettingsApiProvider
    extends $FunctionalProvider<SettingsApi, SettingsApi, SettingsApi>
    with $Provider<SettingsApi> {
  /// Focused appearance-settings capability injected by app composition.
  ///
  /// This is a dependency-injection seam only: it contains no root-client
  /// construction, retries, caching, or workflow.
  AppearanceSettingsApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appearanceSettingsApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appearanceSettingsApiHash();

  @$internal
  @override
  $ProviderElement<SettingsApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SettingsApi create(Ref ref) {
    return appearanceSettingsApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SettingsApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SettingsApi>(value),
    );
  }
}

String _$appearanceSettingsApiHash() =>
    r'9f0df8d91d265e5006fce7d0e7cb7ba699d839b5';

/// Runtime generation context injected by app composition.
///
/// The default is pre-ready; app composition supplies the current runtime
/// identity derived from backend readiness.

@ProviderFor(appearanceRuntimeContext)
final appearanceRuntimeContextProvider = AppearanceRuntimeContextProvider._();

/// Runtime generation context injected by app composition.
///
/// The default is pre-ready; app composition supplies the current runtime
/// identity derived from backend readiness.

final class AppearanceRuntimeContextProvider
    extends
        $FunctionalProvider<
          AppearanceRuntimeContext,
          AppearanceRuntimeContext,
          AppearanceRuntimeContext
        >
    with $Provider<AppearanceRuntimeContext> {
  /// Runtime generation context injected by app composition.
  ///
  /// The default is pre-ready; app composition supplies the current runtime
  /// identity derived from backend readiness.
  AppearanceRuntimeContextProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appearanceRuntimeContextProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appearanceRuntimeContextHash();

  @$internal
  @override
  $ProviderElement<AppearanceRuntimeContext> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AppearanceRuntimeContext create(Ref ref) {
    return appearanceRuntimeContext(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppearanceRuntimeContext value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppearanceRuntimeContext>(value),
    );
  }
}

String _$appearanceRuntimeContextHash() =>
    r'130309e9551244b206d5e12496abbc4c01290310';

/// Appearance reconciliation demand channel injected by app composition.
///
/// This is a dependency-injection seam only: the Settings feature never
/// interprets transport or event-envelope mechanics. The default is an empty
/// source so the feature remains inert without app composition.

@ProviderFor(appearanceReconciliationDemand)
final appearanceReconciliationDemandProvider =
    AppearanceReconciliationDemandProvider._();

/// Appearance reconciliation demand channel injected by app composition.
///
/// This is a dependency-injection seam only: the Settings feature never
/// interprets transport or event-envelope mechanics. The default is an empty
/// source so the feature remains inert without app composition.

final class AppearanceReconciliationDemandProvider
    extends
        $FunctionalProvider<
          AppearanceReconciliationDemandSource,
          AppearanceReconciliationDemandSource,
          AppearanceReconciliationDemandSource
        >
    with $Provider<AppearanceReconciliationDemandSource> {
  /// Appearance reconciliation demand channel injected by app composition.
  ///
  /// This is a dependency-injection seam only: the Settings feature never
  /// interprets transport or event-envelope mechanics. The default is an empty
  /// source so the feature remains inert without app composition.
  AppearanceReconciliationDemandProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appearanceReconciliationDemandProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appearanceReconciliationDemandHash();

  @$internal
  @override
  $ProviderElement<AppearanceReconciliationDemandSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AppearanceReconciliationDemandSource create(Ref ref) {
    return appearanceReconciliationDemand(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppearanceReconciliationDemandSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<AppearanceReconciliationDemandSource>(value),
    );
  }
}

String _$appearanceReconciliationDemandHash() =>
    r'2b9a23374b793584cf19dd2baed54d1bb3ce49cb';
