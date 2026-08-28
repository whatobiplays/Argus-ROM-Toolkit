// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'source_hierarchy_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Query-authoritative incremental hierarchy controller keyed by root.
///
/// It owns bounded per-parent page caches plus transient expansion, selection,
/// and Compact drill-down state. Events are invalidation hints only; every
/// confirmed value comes from a successful focused authoritative read scoped
/// to the current runtime generation.

@ProviderFor(SourceHierarchyController)
final sourceHierarchyControllerProvider = SourceHierarchyControllerFamily._();

/// Query-authoritative incremental hierarchy controller keyed by root.
///
/// It owns bounded per-parent page caches plus transient expansion, selection,
/// and Compact drill-down state. Events are invalidation hints only; every
/// confirmed value comes from a successful focused authoritative read scoped
/// to the current runtime generation.
final class SourceHierarchyControllerProvider
    extends
        $NotifierProvider<
          SourceHierarchyController,
          AsyncValue<SourceHierarchyState>
        > {
  /// Query-authoritative incremental hierarchy controller keyed by root.
  ///
  /// It owns bounded per-parent page caches plus transient expansion, selection,
  /// and Compact drill-down state. Events are invalidation hints only; every
  /// confirmed value comes from a successful focused authoritative read scoped
  /// to the current runtime generation.
  SourceHierarchyControllerProvider._({
    required SourceHierarchyControllerFamily super.from,
    required LibraryRootId super.argument,
  }) : super(
         retry: null,
         name: r'sourceHierarchyControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sourceHierarchyControllerHash();

  @override
  String toString() {
    return r'sourceHierarchyControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SourceHierarchyController create() => SourceHierarchyController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<SourceHierarchyState> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<SourceHierarchyState>>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SourceHierarchyControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sourceHierarchyControllerHash() =>
    r'3608aece7bdb25943b51430015b83b5258c6a106';

/// Query-authoritative incremental hierarchy controller keyed by root.
///
/// It owns bounded per-parent page caches plus transient expansion, selection,
/// and Compact drill-down state. Events are invalidation hints only; every
/// confirmed value comes from a successful focused authoritative read scoped
/// to the current runtime generation.

final class SourceHierarchyControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          SourceHierarchyController,
          AsyncValue<SourceHierarchyState>,
          AsyncValue<SourceHierarchyState>,
          AsyncValue<SourceHierarchyState>,
          LibraryRootId
        > {
  SourceHierarchyControllerFamily._()
    : super(
        retry: null,
        name: r'sourceHierarchyControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Query-authoritative incremental hierarchy controller keyed by root.
  ///
  /// It owns bounded per-parent page caches plus transient expansion, selection,
  /// and Compact drill-down state. Events are invalidation hints only; every
  /// confirmed value comes from a successful focused authoritative read scoped
  /// to the current runtime generation.

  SourceHierarchyControllerProvider call(LibraryRootId rootId) =>
      SourceHierarchyControllerProvider._(argument: rootId, from: this);

  @override
  String toString() => r'sourceHierarchyControllerProvider';
}

/// Query-authoritative incremental hierarchy controller keyed by root.
///
/// It owns bounded per-parent page caches plus transient expansion, selection,
/// and Compact drill-down state. Events are invalidation hints only; every
/// confirmed value comes from a successful focused authoritative read scoped
/// to the current runtime generation.

abstract class _$SourceHierarchyController
    extends $Notifier<AsyncValue<SourceHierarchyState>> {
  late final _$args = ref.$arg as LibraryRootId;
  LibraryRootId get rootId => _$args;

  AsyncValue<SourceHierarchyState> build(LibraryRootId rootId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<SourceHierarchyState>,
              AsyncValue<SourceHierarchyState>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<SourceHierarchyState>,
                AsyncValue<SourceHierarchyState>
              >,
              AsyncValue<SourceHierarchyState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
