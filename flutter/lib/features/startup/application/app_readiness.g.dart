// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_readiness.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Projects authoritative startup state onto the narrow admission policy.

@ProviderFor(appReadiness)
final appReadinessProvider = AppReadinessProvider._();

/// Projects authoritative startup state onto the narrow admission policy.

final class AppReadinessProvider
    extends $FunctionalProvider<AppReadiness, AppReadiness, AppReadiness>
    with $Provider<AppReadiness> {
  /// Projects authoritative startup state onto the narrow admission policy.
  AppReadinessProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appReadinessProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appReadinessHash();

  @$internal
  @override
  $ProviderElement<AppReadiness> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppReadiness create(Ref ref) {
    return appReadiness(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppReadiness value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppReadiness>(value),
    );
  }
}

String _$appReadinessHash() => r'39e424f1cf12ae35a37c568d8f9740642d66bafe';
