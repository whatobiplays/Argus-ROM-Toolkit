// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sources_event_coordinator.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// App-level owner of runtime-event delivery interpretation for Sources.
///
/// This is the only Sources consumer that reads [EventsApi] envelopes and
/// stream continuity. It consumes the shared mapped stream (owned by the root
/// client) and projects each observable delivery condition onto narrow
/// [SourcesReconciliationDemand] signals so the Sources feature can stay
/// transport-agnostic.

@ProviderFor(SourcesEventCoordinator)
final sourcesEventCoordinatorProvider = SourcesEventCoordinatorProvider._();

/// App-level owner of runtime-event delivery interpretation for Sources.
///
/// This is the only Sources consumer that reads [EventsApi] envelopes and
/// stream continuity. It consumes the shared mapped stream (owned by the root
/// client) and projects each observable delivery condition onto narrow
/// [SourcesReconciliationDemand] signals so the Sources feature can stay
/// transport-agnostic.
final class SourcesEventCoordinatorProvider
    extends
        $NotifierProvider<
          SourcesEventCoordinator,
          SourcesReconciliationDemandSource
        > {
  /// App-level owner of runtime-event delivery interpretation for Sources.
  ///
  /// This is the only Sources consumer that reads [EventsApi] envelopes and
  /// stream continuity. It consumes the shared mapped stream (owned by the root
  /// client) and projects each observable delivery condition onto narrow
  /// [SourcesReconciliationDemand] signals so the Sources feature can stay
  /// transport-agnostic.
  SourcesEventCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sourcesEventCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sourcesEventCoordinatorHash();

  @$internal
  @override
  SourcesEventCoordinator create() => SourcesEventCoordinator();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SourcesReconciliationDemandSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SourcesReconciliationDemandSource>(
        value,
      ),
    );
  }
}

String _$sourcesEventCoordinatorHash() =>
    r'f2384d01e6ccc6c51e6bb9fbac7b2dd8096fb82a';

/// App-level owner of runtime-event delivery interpretation for Sources.
///
/// This is the only Sources consumer that reads [EventsApi] envelopes and
/// stream continuity. It consumes the shared mapped stream (owned by the root
/// client) and projects each observable delivery condition onto narrow
/// [SourcesReconciliationDemand] signals so the Sources feature can stay
/// transport-agnostic.

abstract class _$SourcesEventCoordinator
    extends $Notifier<SourcesReconciliationDemandSource> {
  SourcesReconciliationDemandSource build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              SourcesReconciliationDemandSource,
              SourcesReconciliationDemandSource
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                SourcesReconciliationDemandSource,
                SourcesReconciliationDemandSource
              >,
              SourcesReconciliationDemandSource,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
