// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'jobs_list_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One Jobs-branch owner of authoritative list state.
///
/// The list provider is auto-disposed with the Jobs branch; route identity
/// owns branch restoration and the shell never depends on this controller
/// (FE-009 provider lifetime).

@ProviderFor(JobsListController)
final jobsListControllerProvider = JobsListControllerProvider._();

/// One Jobs-branch owner of authoritative list state.
///
/// The list provider is auto-disposed with the Jobs branch; route identity
/// owns branch restoration and the shell never depends on this controller
/// (FE-009 provider lifetime).
final class JobsListControllerProvider
    extends $NotifierProvider<JobsListController, AsyncValue<JobsListState>> {
  /// One Jobs-branch owner of authoritative list state.
  ///
  /// The list provider is auto-disposed with the Jobs branch; route identity
  /// owns branch restoration and the shell never depends on this controller
  /// (FE-009 provider lifetime).
  JobsListControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'jobsListControllerProvider',
        isAutoDispose: true,
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
    r'c928c5bef49720a1159a3f9472c5b174aa2cfe83';

/// One Jobs-branch owner of authoritative list state.
///
/// The list provider is auto-disposed with the Jobs branch; route identity
/// owns branch restoration and the shell never depends on this controller
/// (FE-009 provider lifetime).

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
