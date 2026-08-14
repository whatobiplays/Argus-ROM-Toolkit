// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'appearance_event_coordinator.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// App-level owner of runtime-event delivery interpretation for appearance.
///
/// This is the only appearance consumer that reads [EventsApi] envelopes and
/// stream continuity. It consumes the shared mapped stream (owned by the root
/// client) and projects each observable delivery condition onto exactly one
/// narrow [AppearanceReconciliationDemand] so the Settings feature can stay
/// transport-agnostic.

@ProviderFor(AppearanceEventCoordinator)
final appearanceEventCoordinatorProvider =
    AppearanceEventCoordinatorProvider._();

/// App-level owner of runtime-event delivery interpretation for appearance.
///
/// This is the only appearance consumer that reads [EventsApi] envelopes and
/// stream continuity. It consumes the shared mapped stream (owned by the root
/// client) and projects each observable delivery condition onto exactly one
/// narrow [AppearanceReconciliationDemand] so the Settings feature can stay
/// transport-agnostic.
final class AppearanceEventCoordinatorProvider
    extends
        $NotifierProvider<
          AppearanceEventCoordinator,
          AppearanceReconciliationDemandSource
        > {
  /// App-level owner of runtime-event delivery interpretation for appearance.
  ///
  /// This is the only appearance consumer that reads [EventsApi] envelopes and
  /// stream continuity. It consumes the shared mapped stream (owned by the root
  /// client) and projects each observable delivery condition onto exactly one
  /// narrow [AppearanceReconciliationDemand] so the Settings feature can stay
  /// transport-agnostic.
  AppearanceEventCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appearanceEventCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appearanceEventCoordinatorHash();

  @$internal
  @override
  AppearanceEventCoordinator create() => AppearanceEventCoordinator();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppearanceReconciliationDemandSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<AppearanceReconciliationDemandSource>(value),
    );
  }
}

String _$appearanceEventCoordinatorHash() =>
    r'e72b3673559e0239c1634defc061a6b9ce102f78';

/// App-level owner of runtime-event delivery interpretation for appearance.
///
/// This is the only appearance consumer that reads [EventsApi] envelopes and
/// stream continuity. It consumes the shared mapped stream (owned by the root
/// client) and projects each observable delivery condition onto exactly one
/// narrow [AppearanceReconciliationDemand] so the Settings feature can stay
/// transport-agnostic.

abstract class _$AppearanceEventCoordinator
    extends $Notifier<AppearanceReconciliationDemandSource> {
  AppearanceReconciliationDemandSource build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AppearanceReconciliationDemandSource,
              AppearanceReconciliationDemandSource
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AppearanceReconciliationDemandSource,
                AppearanceReconciliationDemandSource
              >,
              AppearanceReconciliationDemandSource,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
