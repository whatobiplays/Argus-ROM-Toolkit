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

@ProviderFor(sourcesPresentationCapabilities)
final sourcesPresentationCapabilitiesProvider =
    SourcesPresentationCapabilitiesProvider._();

final class SourcesPresentationCapabilitiesProvider
    extends
        $FunctionalProvider<
          SourcesPresentationCapabilities,
          SourcesPresentationCapabilities,
          SourcesPresentationCapabilities
        >
    with $Provider<SourcesPresentationCapabilities> {
  SourcesPresentationCapabilitiesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sourcesPresentationCapabilitiesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sourcesPresentationCapabilitiesHash();

  @$internal
  @override
  $ProviderElement<SourcesPresentationCapabilities> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SourcesPresentationCapabilities create(Ref ref) {
    return sourcesPresentationCapabilities(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SourcesPresentationCapabilities value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SourcesPresentationCapabilities>(
        value,
      ),
    );
  }
}

String _$sourcesPresentationCapabilitiesHash() =>
    r'bba64cf971fda58717d5b2a333e719673f1846eb';

/// Supplies the macOS native picker through the single app-platform
/// composition point. Other hosts receive null and keep their existing picker
/// behavior.

@ProviderFor(macosLibraryFolderPickerApi)
final macosLibraryFolderPickerApiProvider =
    MacosLibraryFolderPickerApiProvider._();

/// Supplies the macOS native picker through the single app-platform
/// composition point. Other hosts receive null and keep their existing picker
/// behavior.

final class MacosLibraryFolderPickerApiProvider
    extends
        $FunctionalProvider<
          MacosLibraryFolderPickerApi?,
          MacosLibraryFolderPickerApi?,
          MacosLibraryFolderPickerApi?
        >
    with $Provider<MacosLibraryFolderPickerApi?> {
  /// Supplies the macOS native picker through the single app-platform
  /// composition point. Other hosts receive null and keep their existing picker
  /// behavior.
  MacosLibraryFolderPickerApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'macosLibraryFolderPickerApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$macosLibraryFolderPickerApiHash();

  @$internal
  @override
  $ProviderElement<MacosLibraryFolderPickerApi?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MacosLibraryFolderPickerApi? create(Ref ref) {
    return macosLibraryFolderPickerApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MacosLibraryFolderPickerApi? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MacosLibraryFolderPickerApi?>(value),
    );
  }
}

String _$macosLibraryFolderPickerApiHash() =>
    r'7f5f4f3f5ab4d1acd9b3dc82768e615a46705c6e';

/// Focused Jobs capability injected for Sources-owned coordination (Scan All
/// ambiguity reconciliation and cancel-and-remove).
///
/// This is a dependency-injection seam only: Sources never reconstructs Jobs
/// truth from events and never owns the full job-detail surface.

@ProviderFor(sourcesJobsApi)
final sourcesJobsApiProvider = SourcesJobsApiProvider._();

/// Focused Jobs capability injected for Sources-owned coordination (Scan All
/// ambiguity reconciliation and cancel-and-remove).
///
/// This is a dependency-injection seam only: Sources never reconstructs Jobs
/// truth from events and never owns the full job-detail surface.

final class SourcesJobsApiProvider
    extends $FunctionalProvider<JobsApi, JobsApi, JobsApi>
    with $Provider<JobsApi> {
  /// Focused Jobs capability injected for Sources-owned coordination (Scan All
  /// ambiguity reconciliation and cancel-and-remove).
  ///
  /// This is a dependency-injection seam only: Sources never reconstructs Jobs
  /// truth from events and never owns the full job-detail surface.
  SourcesJobsApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sourcesJobsApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sourcesJobsApiHash();

  @$internal
  @override
  $ProviderElement<JobsApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  JobsApi create(Ref ref) {
    return sourcesJobsApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(JobsApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<JobsApi>(value),
    );
  }
}

String _$sourcesJobsApiHash() => r'9b0be7b50ef7a316a3a9c527116fc2e13c681d67';

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
