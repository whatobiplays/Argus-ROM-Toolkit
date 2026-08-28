// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'source_entry_detail_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Focused authoritative detail for one selected source entry.
///
/// The detail survives stable-ID moves even when the new hierarchy location is
/// not loaded, and it refreshes through a focused `getSourceEntry` read on any
/// source invalidation for the owning root (one bounded query, never an N+1
/// pattern).

@ProviderFor(SourceEntryDetailController)
final sourceEntryDetailControllerProvider =
    SourceEntryDetailControllerFamily._();

/// Focused authoritative detail for one selected source entry.
///
/// The detail survives stable-ID moves even when the new hierarchy location is
/// not loaded, and it refreshes through a focused `getSourceEntry` read on any
/// source invalidation for the owning root (one bounded query, never an N+1
/// pattern).
final class SourceEntryDetailControllerProvider
    extends
        $AsyncNotifierProvider<SourceEntryDetailController, SourceEntryDetail> {
  /// Focused authoritative detail for one selected source entry.
  ///
  /// The detail survives stable-ID moves even when the new hierarchy location is
  /// not loaded, and it refreshes through a focused `getSourceEntry` read on any
  /// source invalidation for the owning root (one bounded query, never an N+1
  /// pattern).
  SourceEntryDetailControllerProvider._({
    required SourceEntryDetailControllerFamily super.from,
    required ({LibraryRootId rootId, SourceEntryId sourceEntryId})
    super.argument,
  }) : super(
         retry: null,
         name: r'sourceEntryDetailControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sourceEntryDetailControllerHash();

  @override
  String toString() {
    return r'sourceEntryDetailControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  SourceEntryDetailController create() => SourceEntryDetailController();

  @override
  bool operator ==(Object other) {
    return other is SourceEntryDetailControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sourceEntryDetailControllerHash() =>
    r'9ff0636b8a416375898a14c527a81a6bd0607a17';

/// Focused authoritative detail for one selected source entry.
///
/// The detail survives stable-ID moves even when the new hierarchy location is
/// not loaded, and it refreshes through a focused `getSourceEntry` read on any
/// source invalidation for the owning root (one bounded query, never an N+1
/// pattern).

final class SourceEntryDetailControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          SourceEntryDetailController,
          AsyncValue<SourceEntryDetail>,
          SourceEntryDetail,
          FutureOr<SourceEntryDetail>,
          ({LibraryRootId rootId, SourceEntryId sourceEntryId})
        > {
  SourceEntryDetailControllerFamily._()
    : super(
        retry: null,
        name: r'sourceEntryDetailControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Focused authoritative detail for one selected source entry.
  ///
  /// The detail survives stable-ID moves even when the new hierarchy location is
  /// not loaded, and it refreshes through a focused `getSourceEntry` read on any
  /// source invalidation for the owning root (one bounded query, never an N+1
  /// pattern).

  SourceEntryDetailControllerProvider call({
    required LibraryRootId rootId,
    required SourceEntryId sourceEntryId,
  }) => SourceEntryDetailControllerProvider._(
    argument: (rootId: rootId, sourceEntryId: sourceEntryId),
    from: this,
  );

  @override
  String toString() => r'sourceEntryDetailControllerProvider';
}

/// Focused authoritative detail for one selected source entry.
///
/// The detail survives stable-ID moves even when the new hierarchy location is
/// not loaded, and it refreshes through a focused `getSourceEntry` read on any
/// source invalidation for the owning root (one bounded query, never an N+1
/// pattern).

abstract class _$SourceEntryDetailController
    extends $AsyncNotifier<SourceEntryDetail> {
  late final _$args =
      ref.$arg as ({LibraryRootId rootId, SourceEntryId sourceEntryId});
  LibraryRootId get rootId => _$args.rootId;
  SourceEntryId get sourceEntryId => _$args.sourceEntryId;

  FutureOr<SourceEntryDetail> build({
    required LibraryRootId rootId,
    required SourceEntryId sourceEntryId,
  });
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<SourceEntryDetail>, SourceEntryDetail>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<SourceEntryDetail>, SourceEntryDetail>,
              AsyncValue<SourceEntryDetail>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(rootId: _$args.rootId, sourceEntryId: _$args.sourceEntryId),
    );
  }
}
