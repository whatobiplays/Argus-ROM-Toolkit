// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'jobs_event_coordinator.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// App-level owner of runtime-event delivery interpretation for Jobs.
///
/// This is the only Jobs consumer that reads [EventsApi] envelopes and stream
/// continuity. Job notifications only trigger authoritative reconciliation;
/// they never mutate lifecycle state locally.

@ProviderFor(JobsEventCoordinator)
final jobsEventCoordinatorProvider = JobsEventCoordinatorProvider._();

/// App-level owner of runtime-event delivery interpretation for Jobs.
///
/// This is the only Jobs consumer that reads [EventsApi] envelopes and stream
/// continuity. Job notifications only trigger authoritative reconciliation;
/// they never mutate lifecycle state locally.
final class JobsEventCoordinatorProvider
    extends
        $NotifierProvider<
          JobsEventCoordinator,
          JobsReconciliationDemandSource
        > {
  /// App-level owner of runtime-event delivery interpretation for Jobs.
  ///
  /// This is the only Jobs consumer that reads [EventsApi] envelopes and stream
  /// continuity. Job notifications only trigger authoritative reconciliation;
  /// they never mutate lifecycle state locally.
  JobsEventCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'jobsEventCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$jobsEventCoordinatorHash();

  @$internal
  @override
  JobsEventCoordinator create() => JobsEventCoordinator();

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

String _$jobsEventCoordinatorHash() =>
    r'7405a5eff117f7135645085f4576db1820bca45a';

/// App-level owner of runtime-event delivery interpretation for Jobs.
///
/// This is the only Jobs consumer that reads [EventsApi] envelopes and stream
/// continuity. Job notifications only trigger authoritative reconciliation;
/// they never mutate lifecycle state locally.

abstract class _$JobsEventCoordinator
    extends $Notifier<JobsReconciliationDemandSource> {
  JobsReconciliationDemandSource build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              JobsReconciliationDemandSource,
              JobsReconciliationDemandSource
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                JobsReconciliationDemandSource,
                JobsReconciliationDemandSource
              >,
              JobsReconciliationDemandSource,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
