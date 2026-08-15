// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'add_library_folder_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One application-lifetime owner of the root-only add workflow state.

@ProviderFor(SourcesAddLibraryFolderController)
final sourcesAddLibraryFolderControllerProvider =
    SourcesAddLibraryFolderControllerProvider._();

/// One application-lifetime owner of the root-only add workflow state.
final class SourcesAddLibraryFolderControllerProvider
    extends
        $NotifierProvider<
          SourcesAddLibraryFolderController,
          SourcesAddOperation
        > {
  /// One application-lifetime owner of the root-only add workflow state.
  SourcesAddLibraryFolderControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sourcesAddLibraryFolderControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$sourcesAddLibraryFolderControllerHash();

  @$internal
  @override
  SourcesAddLibraryFolderController create() =>
      SourcesAddLibraryFolderController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SourcesAddOperation value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SourcesAddOperation>(value),
    );
  }
}

String _$sourcesAddLibraryFolderControllerHash() =>
    r'c1ca950d38352c0d8ee769f7bb6e56b51384c3fa';

/// One application-lifetime owner of the root-only add workflow state.

abstract class _$SourcesAddLibraryFolderController
    extends $Notifier<SourcesAddOperation> {
  SourcesAddOperation build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SourcesAddOperation, SourcesAddOperation>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SourcesAddOperation, SourcesAddOperation>,
              SourcesAddOperation,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
