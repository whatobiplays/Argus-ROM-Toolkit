// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'root_detail_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One application-lifetime owner of authoritative root-detail state.

@ProviderFor(SourcesRootDetailController)
final sourcesRootDetailControllerProvider =
    SourcesRootDetailControllerFamily._();

/// One application-lifetime owner of authoritative root-detail state.
final class SourcesRootDetailControllerProvider
    extends
        $NotifierProvider<
          SourcesRootDetailController,
          AsyncValue<SourcesRootDetailState>
        > {
  /// One application-lifetime owner of authoritative root-detail state.
  SourcesRootDetailControllerProvider._({
    required SourcesRootDetailControllerFamily super.from,
    required LibraryRootId super.argument,
  }) : super(
         retry: null,
         name: r'sourcesRootDetailControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sourcesRootDetailControllerHash();

  @override
  String toString() {
    return r'sourcesRootDetailControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SourcesRootDetailController create() => SourcesRootDetailController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<SourcesRootDetailState> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<SourcesRootDetailState>>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SourcesRootDetailControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sourcesRootDetailControllerHash() =>
    r'3c704ade1df6577302e13902c69da3430923cee5';

/// One application-lifetime owner of authoritative root-detail state.

final class SourcesRootDetailControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          SourcesRootDetailController,
          AsyncValue<SourcesRootDetailState>,
          AsyncValue<SourcesRootDetailState>,
          AsyncValue<SourcesRootDetailState>,
          LibraryRootId
        > {
  SourcesRootDetailControllerFamily._()
    : super(
        retry: null,
        name: r'sourcesRootDetailControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// One application-lifetime owner of authoritative root-detail state.

  SourcesRootDetailControllerProvider call(LibraryRootId rootId) =>
      SourcesRootDetailControllerProvider._(argument: rootId, from: this);

  @override
  String toString() => r'sourcesRootDetailControllerProvider';
}

/// One application-lifetime owner of authoritative root-detail state.

abstract class _$SourcesRootDetailController
    extends $Notifier<AsyncValue<SourcesRootDetailState>> {
  late final _$args = ref.$arg as LibraryRootId;
  LibraryRootId get rootId => _$args;

  AsyncValue<SourcesRootDetailState> build(LibraryRootId rootId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<SourcesRootDetailState>,
              AsyncValue<SourcesRootDetailState>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<SourcesRootDetailState>,
                AsyncValue<SourcesRootDetailState>
              >,
              AsyncValue<SourcesRootDetailState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
