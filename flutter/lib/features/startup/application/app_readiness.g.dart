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

/// Projects the current ready runtime identity, or null while backend
/// readiness has not been certified.
///
/// This is the narrow typed seam app composition uses to keep the appearance
/// feature bound to the runtime generation that owns settings authority.

@ProviderFor(readyRuntimeInstanceId)
final readyRuntimeInstanceIdProvider = ReadyRuntimeInstanceIdProvider._();

/// Projects the current ready runtime identity, or null while backend
/// readiness has not been certified.
///
/// This is the narrow typed seam app composition uses to keep the appearance
/// feature bound to the runtime generation that owns settings authority.

final class ReadyRuntimeInstanceIdProvider
    extends
        $FunctionalProvider<
          RuntimeInstanceId?,
          RuntimeInstanceId?,
          RuntimeInstanceId?
        >
    with $Provider<RuntimeInstanceId?> {
  /// Projects the current ready runtime identity, or null while backend
  /// readiness has not been certified.
  ///
  /// This is the narrow typed seam app composition uses to keep the appearance
  /// feature bound to the runtime generation that owns settings authority.
  ReadyRuntimeInstanceIdProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'readyRuntimeInstanceIdProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$readyRuntimeInstanceIdHash();

  @$internal
  @override
  $ProviderElement<RuntimeInstanceId?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RuntimeInstanceId? create(Ref ref) {
    return readyRuntimeInstanceId(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RuntimeInstanceId? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RuntimeInstanceId?>(value),
    );
  }
}

String _$readyRuntimeInstanceIdHash() =>
    r'e3af6b8017f5d8db4b3bed37be68a1e9da6a9a27';
