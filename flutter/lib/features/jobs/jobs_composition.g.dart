// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'jobs_composition.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Focused Jobs capability injected by app composition.

@ProviderFor(jobsApi)
final jobsApiProvider = JobsApiProvider._();

/// Focused Jobs capability injected by app composition.

final class JobsApiProvider
    extends $FunctionalProvider<JobsApi, JobsApi, JobsApi>
    with $Provider<JobsApi> {
  /// Focused Jobs capability injected by app composition.
  JobsApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'jobsApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$jobsApiHash();

  @$internal
  @override
  $ProviderElement<JobsApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  JobsApi create(Ref ref) {
    return jobsApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(JobsApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<JobsApi>(value),
    );
  }
}

String _$jobsApiHash() => r'90ce2da439ed7e80f26786f1ac5fdbe4f36bf9a7';

/// Runtime generation context injected by app composition.

@ProviderFor(jobsRuntimeContext)
final jobsRuntimeContextProvider = JobsRuntimeContextProvider._();

/// Runtime generation context injected by app composition.

final class JobsRuntimeContextProvider
    extends
        $FunctionalProvider<
          JobsRuntimeContext,
          JobsRuntimeContext,
          JobsRuntimeContext
        >
    with $Provider<JobsRuntimeContext> {
  /// Runtime generation context injected by app composition.
  JobsRuntimeContextProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'jobsRuntimeContextProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$jobsRuntimeContextHash();

  @$internal
  @override
  $ProviderElement<JobsRuntimeContext> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  JobsRuntimeContext create(Ref ref) {
    return jobsRuntimeContext(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(JobsRuntimeContext value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<JobsRuntimeContext>(value),
    );
  }
}

String _$jobsRuntimeContextHash() =>
    r'c9488df1603f01cedc9d65d23387b3a38dfc833e';

/// Jobs reconciliation demand channel injected by app composition.

@ProviderFor(jobsReconciliationDemand)
final jobsReconciliationDemandProvider = JobsReconciliationDemandProvider._();

/// Jobs reconciliation demand channel injected by app composition.

final class JobsReconciliationDemandProvider
    extends
        $FunctionalProvider<
          JobsReconciliationDemandSource,
          JobsReconciliationDemandSource,
          JobsReconciliationDemandSource
        >
    with $Provider<JobsReconciliationDemandSource> {
  /// Jobs reconciliation demand channel injected by app composition.
  JobsReconciliationDemandProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'jobsReconciliationDemandProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$jobsReconciliationDemandHash();

  @$internal
  @override
  $ProviderElement<JobsReconciliationDemandSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  JobsReconciliationDemandSource create(Ref ref) {
    return jobsReconciliationDemand(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(JobsReconciliationDemandSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<JobsReconciliationDemandSource>(
        value,
      ),
    );
  }
}

String _$jobsReconciliationDemandHash() =>
    r'0fbd002763706529801c0f7cf8b2f5695abe8367';
