// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'job_detail_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One application-lifetime owner of authoritative job-detail state.

@ProviderFor(JobDetailController)
final jobDetailControllerProvider = JobDetailControllerFamily._();

/// One application-lifetime owner of authoritative job-detail state.
final class JobDetailControllerProvider
    extends $NotifierProvider<JobDetailController, AsyncValue<JobDetailState>> {
  /// One application-lifetime owner of authoritative job-detail state.
  JobDetailControllerProvider._({
    required JobDetailControllerFamily super.from,
    required JobRunId super.argument,
  }) : super(
         retry: null,
         name: r'jobDetailControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$jobDetailControllerHash();

  @override
  String toString() {
    return r'jobDetailControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  JobDetailController create() => JobDetailController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<JobDetailState> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<JobDetailState>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is JobDetailControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$jobDetailControllerHash() =>
    r'cd9be23983b8732ae4916375dd86d6ce72fdfda4';

/// One application-lifetime owner of authoritative job-detail state.

final class JobDetailControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          JobDetailController,
          AsyncValue<JobDetailState>,
          AsyncValue<JobDetailState>,
          AsyncValue<JobDetailState>,
          JobRunId
        > {
  JobDetailControllerFamily._()
    : super(
        retry: null,
        name: r'jobDetailControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// One application-lifetime owner of authoritative job-detail state.

  JobDetailControllerProvider call(JobRunId jobRunId) =>
      JobDetailControllerProvider._(argument: jobRunId, from: this);

  @override
  String toString() => r'jobDetailControllerProvider';
}

/// One application-lifetime owner of authoritative job-detail state.

abstract class _$JobDetailController
    extends $Notifier<AsyncValue<JobDetailState>> {
  late final _$args = ref.$arg as JobRunId;
  JobRunId get jobRunId => _$args;

  AsyncValue<JobDetailState> build(JobRunId jobRunId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<JobDetailState>, AsyncValue<JobDetailState>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<JobDetailState>,
                AsyncValue<JobDetailState>
              >,
              AsyncValue<JobDetailState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
