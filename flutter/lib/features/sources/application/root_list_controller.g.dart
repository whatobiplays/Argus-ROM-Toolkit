// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'root_list_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One application-lifetime owner of query-authoritative root-list state.
///
/// The outer [AsyncValue] represents whether usable authority exists: loading
/// until the first read completes, error when that initial read fails, and
/// ready afterwards. Confirmed roots remain renderable during refresh and
/// runtime adoption; only a successful focused read changes them.

@ProviderFor(SourcesRootListController)
final sourcesRootListControllerProvider = SourcesRootListControllerProvider._();

/// One application-lifetime owner of query-authoritative root-list state.
///
/// The outer [AsyncValue] represents whether usable authority exists: loading
/// until the first read completes, error when that initial read fails, and
/// ready afterwards. Confirmed roots remain renderable during refresh and
/// runtime adoption; only a successful focused read changes them.
final class SourcesRootListControllerProvider
    extends
        $NotifierProvider<
          SourcesRootListController,
          AsyncValue<SourcesRootListState>
        > {
  /// One application-lifetime owner of query-authoritative root-list state.
  ///
  /// The outer [AsyncValue] represents whether usable authority exists: loading
  /// until the first read completes, error when that initial read fails, and
  /// ready afterwards. Confirmed roots remain renderable during refresh and
  /// runtime adoption; only a successful focused read changes them.
  SourcesRootListControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sourcesRootListControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sourcesRootListControllerHash();

  @$internal
  @override
  SourcesRootListController create() => SourcesRootListController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<SourcesRootListState> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<SourcesRootListState>>(
        value,
      ),
    );
  }
}

String _$sourcesRootListControllerHash() =>
    r'cd9e182a9c88e36e19652cb9316120d9c497ed73';

/// One application-lifetime owner of query-authoritative root-list state.
///
/// The outer [AsyncValue] represents whether usable authority exists: loading
/// until the first read completes, error when that initial read fails, and
/// ready afterwards. Confirmed roots remain renderable during refresh and
/// runtime adoption; only a successful focused read changes them.

abstract class _$SourcesRootListController
    extends $Notifier<AsyncValue<SourcesRootListState>> {
  AsyncValue<SourcesRootListState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<SourcesRootListState>,
              AsyncValue<SourcesRootListState>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<SourcesRootListState>,
                AsyncValue<SourcesRootListState>
              >,
              AsyncValue<SourcesRootListState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
