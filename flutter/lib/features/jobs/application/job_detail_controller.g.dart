// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'job_detail_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One identity-parameterized owner of authoritative job-detail state.
///
/// The detail provider is auto-disposed and recreatable per routed
/// `JobRunId`; it is not retained as an application-lifetime cache (FE-009).

@ProviderFor(JobDetailController)
final jobDetailControllerProvider = JobDetailControllerFamily._();

/// One identity-parameterized owner of authoritative job-detail state.
///
/// The detail provider is auto-disposed and recreatable per routed
/// `JobRunId`; it is not retained as an application-lifetime cache (FE-009).
final class JobDetailControllerProvider
    extends $NotifierProvider<JobDetailController, AsyncValue<JobDetailState>> {
  /// One identity-parameterized owner of authoritative job-detail state.
  ///
  /// The detail provider is auto-disposed and recreatable per routed
  /// `JobRunId`; it is not retained as an application-lifetime cache (FE-009).
  JobDetailControllerProvider._({
    required JobDetailControllerFamily super.from,
    required JobRunId super.argument,
  }) : super(
         retry: null,
         name: r'jobDetailControllerProvider',
         isAutoDispose: true,
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
    r'99ebeb82ccc6aeeed99ef8cff6134bc031d1ec0b';

/// One identity-parameterized owner of authoritative job-detail state.
///
/// The detail provider is auto-disposed and recreatable per routed
/// `JobRunId`; it is not retained as an application-lifetime cache (FE-009).

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
        isAutoDispose: true,
      );

  /// One identity-parameterized owner of authoritative job-detail state.
  ///
  /// The detail provider is auto-disposed and recreatable per routed
  /// `JobRunId`; it is not retained as an application-lifetime cache (FE-009).

  JobDetailControllerProvider call(JobRunId jobRunId) =>
      JobDetailControllerProvider._(argument: jobRunId, from: this);

  @override
  String toString() => r'jobDetailControllerProvider';
}

/// One identity-parameterized owner of authoritative job-detail state.
///
/// The detail provider is auto-disposed and recreatable per routed
/// `JobRunId`; it is not retained as an application-lifetime cache (FE-009).

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
