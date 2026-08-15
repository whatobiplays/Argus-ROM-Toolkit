// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'jobs_list_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One application-lifetime owner of authoritative Jobs list state.

@ProviderFor(JobsListController)
final jobsListControllerProvider = JobsListControllerProvider._();

/// One application-lifetime owner of authoritative Jobs list state.
final class JobsListControllerProvider
    extends $NotifierProvider<JobsListController, AsyncValue<JobsListState>> {
  /// One application-lifetime owner of authoritative Jobs list state.
  JobsListControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'jobsListControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$jobsListControllerHash();

  @$internal
  @override
  JobsListController create() => JobsListController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<JobsListState> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<JobsListState>>(value),
    );
  }
}

String _$jobsListControllerHash() =>
    r'92d58255cb0d47216ad0561fe47e5dc895904285';

/// One application-lifetime owner of authoritative Jobs list state.

abstract class _$JobsListController
    extends $Notifier<AsyncValue<JobsListState>> {
  AsyncValue<JobsListState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<JobsListState>, AsyncValue<JobsListState>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<JobsListState>, AsyncValue<JobsListState>>,
              AsyncValue<JobsListState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
