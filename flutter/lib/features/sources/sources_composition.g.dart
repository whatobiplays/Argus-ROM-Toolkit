// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sources_composition.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Focused Sources capability injected by app composition.
///
/// This is a dependency-injection seam only: it contains no root-client
/// construction, retries, caching, or workflow.

@ProviderFor(sourcesApi)
final sourcesApiProvider = SourcesApiProvider._();

/// Focused Sources capability injected by app composition.
///
/// This is a dependency-injection seam only: it contains no root-client
/// construction, retries, caching, or workflow.

final class SourcesApiProvider
    extends $FunctionalProvider<SourcesApi, SourcesApi, SourcesApi>
    with $Provider<SourcesApi> {
  /// Focused Sources capability injected by app composition.
  ///
  /// This is a dependency-injection seam only: it contains no root-client
  /// construction, retries, caching, or workflow.
  SourcesApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sourcesApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sourcesApiHash();

  @$internal
  @override
  $ProviderElement<SourcesApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SourcesApi create(Ref ref) {
    return sourcesApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SourcesApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SourcesApi>(value),
    );
  }
}

String _$sourcesApiHash() => r'95355846b91c5ed32b66889d4e06b6c84920a6dd';

/// Runtime generation context injected by app composition.
///
/// The default is pre-ready; app composition supplies the current runtime
/// identity derived from backend readiness.

@ProviderFor(sourcesRuntimeContext)
final sourcesRuntimeContextProvider = SourcesRuntimeContextProvider._();

/// Runtime generation context injected by app composition.
///
/// The default is pre-ready; app composition supplies the current runtime
/// identity derived from backend readiness.

final class SourcesRuntimeContextProvider
    extends
        $FunctionalProvider<
          SourcesRuntimeContext,
          SourcesRuntimeContext,
          SourcesRuntimeContext
        >
    with $Provider<SourcesRuntimeContext> {
  /// Runtime generation context injected by app composition.
  ///
  /// The default is pre-ready; app composition supplies the current runtime
  /// identity derived from backend readiness.
  SourcesRuntimeContextProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sourcesRuntimeContextProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sourcesRuntimeContextHash();

  @$internal
  @override
  $ProviderElement<SourcesRuntimeContext> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SourcesRuntimeContext create(Ref ref) {
    return sourcesRuntimeContext(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SourcesRuntimeContext value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SourcesRuntimeContext>(value),
    );
  }
}

String _$sourcesRuntimeContextHash() =>
    r'8dfc16d5f8ffc3caec5b6c1e41cfc803383368ca';

/// Sources reconciliation demand channel injected by app composition.
///
/// This is a dependency-injection seam only: the Sources feature never
/// interprets transport or event-envelope mechanics. The default is an empty
/// source so the feature remains inert without app composition.

@ProviderFor(sourcesReconciliationDemand)
final sourcesReconciliationDemandProvider =
    SourcesReconciliationDemandProvider._();

/// Sources reconciliation demand channel injected by app composition.
///
/// This is a dependency-injection seam only: the Sources feature never
/// interprets transport or event-envelope mechanics. The default is an empty
/// source so the feature remains inert without app composition.

final class SourcesReconciliationDemandProvider
    extends
        $FunctionalProvider<
          SourcesReconciliationDemandSource,
          SourcesReconciliationDemandSource,
          SourcesReconciliationDemandSource
        >
    with $Provider<SourcesReconciliationDemandSource> {
  /// Sources reconciliation demand channel injected by app composition.
  ///
  /// This is a dependency-injection seam only: the Sources feature never
  /// interprets transport or event-envelope mechanics. The default is an empty
  /// source so the feature remains inert without app composition.
  SourcesReconciliationDemandProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sourcesReconciliationDemandProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sourcesReconciliationDemandHash();

  @$internal
  @override
  $ProviderElement<SourcesReconciliationDemandSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SourcesReconciliationDemandSource create(Ref ref) {
    return sourcesReconciliationDemand(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SourcesReconciliationDemandSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SourcesReconciliationDemandSource>(
        value,
      ),
    );
  }
}

String _$sourcesReconciliationDemandHash() =>
    r'121a1505527d93375d4519f790dbf3aaeb69a164';
