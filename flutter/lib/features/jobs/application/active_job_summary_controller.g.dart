// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'active_job_summary_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Narrow app/shell-safe active-job summary.
///
/// This provider is the only shell dependency: it never depends on Jobs list
/// or detail controllers, Sources state, or locally initiated mutations.

@ProviderFor(ActiveJobSummaryController)
final activeJobSummaryControllerProvider =
    ActiveJobSummaryControllerProvider._();

/// Narrow app/shell-safe active-job summary.
///
/// This provider is the only shell dependency: it never depends on Jobs list
/// or detail controllers, Sources state, or locally initiated mutations.
final class ActiveJobSummaryControllerProvider
    extends
        $NotifierProvider<
          ActiveJobSummaryController,
          AsyncValue<ActiveJobSummary>
        > {
  /// Narrow app/shell-safe active-job summary.
  ///
  /// This provider is the only shell dependency: it never depends on Jobs list
  /// or detail controllers, Sources state, or locally initiated mutations.
  ActiveJobSummaryControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeJobSummaryControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeJobSummaryControllerHash();

  @$internal
  @override
  ActiveJobSummaryController create() => ActiveJobSummaryController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<ActiveJobSummary> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<ActiveJobSummary>>(value),
    );
  }
}

String _$activeJobSummaryControllerHash() =>
    r'27a98ffdfbaddc2a8bf3a1378bd39ccf9fba88f7';

/// Narrow app/shell-safe active-job summary.
///
/// This provider is the only shell dependency: it never depends on Jobs list
/// or detail controllers, Sources state, or locally initiated mutations.

abstract class _$ActiveJobSummaryController
    extends $Notifier<AsyncValue<ActiveJobSummary>> {
  AsyncValue<ActiveJobSummary> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<ActiveJobSummary>, AsyncValue<ActiveJobSummary>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<ActiveJobSummary>,
                AsyncValue<ActiveJobSummary>
              >,
              AsyncValue<ActiveJobSummary>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
