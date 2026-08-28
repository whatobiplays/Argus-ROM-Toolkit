// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'application_lifecycle_coordinator.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Sole app-lifetime observer for lifecycle transitions.
///
/// The coordinator certifies Android readiness after a resume, then publishes
/// one bounded demand for app composition to map onto existing feature seams.
/// It deliberately does not retain or register feature controllers.

@ProviderFor(ApplicationLifecycleCoordinator)
final applicationLifecycleCoordinatorProvider =
    ApplicationLifecycleCoordinatorProvider._();

/// Sole app-lifetime observer for lifecycle transitions.
///
/// The coordinator certifies Android readiness after a resume, then publishes
/// one bounded demand for app composition to map onto existing feature seams.
/// It deliberately does not retain or register feature controllers.
final class ApplicationLifecycleCoordinatorProvider
    extends
        $NotifierProvider<
          ApplicationLifecycleCoordinator,
          ApplicationLifecycleReconciliationDemandSource
        > {
  /// Sole app-lifetime observer for lifecycle transitions.
  ///
  /// The coordinator certifies Android readiness after a resume, then publishes
  /// one bounded demand for app composition to map onto existing feature seams.
  /// It deliberately does not retain or register feature controllers.
  ApplicationLifecycleCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'applicationLifecycleCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$applicationLifecycleCoordinatorHash();

  @$internal
  @override
  ApplicationLifecycleCoordinator create() => ApplicationLifecycleCoordinator();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    ApplicationLifecycleReconciliationDemandSource value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<ApplicationLifecycleReconciliationDemandSource>(
            value,
          ),
    );
  }
}

String _$applicationLifecycleCoordinatorHash() =>
    r'31bf8dc1291aedf1d408ae56fcc361a2ec8a6e46';

/// Sole app-lifetime observer for lifecycle transitions.
///
/// The coordinator certifies Android readiness after a resume, then publishes
/// one bounded demand for app composition to map onto existing feature seams.
/// It deliberately does not retain or register feature controllers.

abstract class _$ApplicationLifecycleCoordinator
    extends $Notifier<ApplicationLifecycleReconciliationDemandSource> {
  ApplicationLifecycleReconciliationDemandSource build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              ApplicationLifecycleReconciliationDemandSource,
              ApplicationLifecycleReconciliationDemandSource
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                ApplicationLifecycleReconciliationDemandSource,
                ApplicationLifecycleReconciliationDemandSource
              >,
              ApplicationLifecycleReconciliationDemandSource,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Exposes the coordinator's read-only signal to app composition.

@ProviderFor(applicationLifecycleReconciliationDemand)
final applicationLifecycleReconciliationDemandProvider =
    ApplicationLifecycleReconciliationDemandProvider._();

/// Exposes the coordinator's read-only signal to app composition.

final class ApplicationLifecycleReconciliationDemandProvider
    extends
        $FunctionalProvider<
          ApplicationLifecycleReconciliationDemandSource,
          ApplicationLifecycleReconciliationDemandSource,
          ApplicationLifecycleReconciliationDemandSource
        >
    with $Provider<ApplicationLifecycleReconciliationDemandSource> {
  /// Exposes the coordinator's read-only signal to app composition.
  ApplicationLifecycleReconciliationDemandProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'applicationLifecycleReconciliationDemandProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$applicationLifecycleReconciliationDemandHash();

  @$internal
  @override
  $ProviderElement<ApplicationLifecycleReconciliationDemandSource>
  $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  ApplicationLifecycleReconciliationDemandSource create(Ref ref) {
    return applicationLifecycleReconciliationDemand(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    ApplicationLifecycleReconciliationDemandSource value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<ApplicationLifecycleReconciliationDemandSource>(
            value,
          ),
    );
  }
}

String _$applicationLifecycleReconciliationDemandHash() =>
    r'c803cfc9d07e35404c6417979bc7d89a95c23049';
