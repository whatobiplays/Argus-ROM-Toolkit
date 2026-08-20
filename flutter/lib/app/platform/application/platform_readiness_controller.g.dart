// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'platform_readiness_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// DI seam for the platform host; app composition always supplies it.

@ProviderFor(platformHostApi)
final platformHostApiProvider = PlatformHostApiProvider._();

/// DI seam for the platform host; app composition always supplies it.

final class PlatformHostApiProvider
    extends
        $FunctionalProvider<PlatformHostApi, PlatformHostApi, PlatformHostApi>
    with $Provider<PlatformHostApi> {
  /// DI seam for the platform host; app composition always supplies it.
  PlatformHostApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'platformHostApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$platformHostApiHash();

  @$internal
  @override
  $ProviderElement<PlatformHostApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PlatformHostApi create(Ref ref) {
    return platformHostApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlatformHostApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlatformHostApi>(value),
    );
  }
}

String _$platformHostApiHash() => r'93283cca848921b6da681b3bca99fcb090a2097f';

@ProviderFor(platformMountedVolumesReader)
final platformMountedVolumesReaderProvider =
    PlatformMountedVolumesReaderProvider._();

final class PlatformMountedVolumesReaderProvider
    extends
        $FunctionalProvider<
          PlatformMountedVolumesReader?,
          PlatformMountedVolumesReader?,
          PlatformMountedVolumesReader?
        >
    with $Provider<PlatformMountedVolumesReader?> {
  PlatformMountedVolumesReaderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'platformMountedVolumesReaderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$platformMountedVolumesReaderHash();

  @$internal
  @override
  $ProviderElement<PlatformMountedVolumesReader?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PlatformMountedVolumesReader? create(Ref ref) {
    return platformMountedVolumesReader(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlatformMountedVolumesReader? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlatformMountedVolumesReader?>(
        value,
      ),
    );
  }
}

String _$platformMountedVolumesReaderHash() =>
    r'8d60da22c6ee71c6ad153f651076bbcf055856c7';

/// Exposes the readiness-owned storage transition channel without rebuilding
/// it every time the readiness state changes.

@ProviderFor(platformStorageReconciliationDemand)
final platformStorageReconciliationDemandProvider =
    PlatformStorageReconciliationDemandProvider._();

/// Exposes the readiness-owned storage transition channel without rebuilding
/// it every time the readiness state changes.

final class PlatformStorageReconciliationDemandProvider
    extends
        $FunctionalProvider<
          PlatformStorageReconciliationDemandSource,
          PlatformStorageReconciliationDemandSource,
          PlatformStorageReconciliationDemandSource
        >
    with $Provider<PlatformStorageReconciliationDemandSource> {
  /// Exposes the readiness-owned storage transition channel without rebuilding
  /// it every time the readiness state changes.
  PlatformStorageReconciliationDemandProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'platformStorageReconciliationDemandProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() =>
      _$platformStorageReconciliationDemandHash();

  @$internal
  @override
  $ProviderElement<PlatformStorageReconciliationDemandSource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PlatformStorageReconciliationDemandSource create(Ref ref) {
    return platformStorageReconciliationDemand(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlatformStorageReconciliationDemandSource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<PlatformStorageReconciliationDemandSource>(value),
    );
  }
}

String _$platformStorageReconciliationDemandHash() =>
    r'55d1bf932ae92db8d451bd8da581e4d23e6386f8';

/// Keep-alive authority for live platform readiness.
///
/// The first Ready snapshot latches the runtime configuration for the
/// process lifetime. Later permission revocation hides the application
/// through the readiness gate but never invalidates the client factory or
/// replaces an already initialized root runtime.

@ProviderFor(PlatformReadinessController)
final platformReadinessControllerProvider =
    PlatformReadinessControllerProvider._();

/// Keep-alive authority for live platform readiness.
///
/// The first Ready snapshot latches the runtime configuration for the
/// process lifetime. Later permission revocation hides the application
/// through the readiness gate but never invalidates the client factory or
/// replaces an already initialized root runtime.
final class PlatformReadinessControllerProvider
    extends
        $NotifierProvider<PlatformReadinessController, PlatformReadinessState> {
  /// Keep-alive authority for live platform readiness.
  ///
  /// The first Ready snapshot latches the runtime configuration for the
  /// process lifetime. Later permission revocation hides the application
  /// through the readiness gate but never invalidates the client factory or
  /// replaces an already initialized root runtime.
  PlatformReadinessControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'platformReadinessControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$platformReadinessControllerHash();

  @$internal
  @override
  PlatformReadinessController create() => PlatformReadinessController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlatformReadinessState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlatformReadinessState>(value),
    );
  }
}

String _$platformReadinessControllerHash() =>
    r'54bb2544b18a0260b497f9a5674f567f927f5d70';

/// Keep-alive authority for live platform readiness.
///
/// The first Ready snapshot latches the runtime configuration for the
/// process lifetime. Later permission revocation hides the application
/// through the readiness gate but never invalidates the client factory or
/// replaces an already initialized root runtime.

abstract class _$PlatformReadinessController
    extends $Notifier<PlatformReadinessState> {
  PlatformReadinessState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<PlatformReadinessState, PlatformReadinessState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PlatformReadinessState, PlatformReadinessState>,
              PlatformReadinessState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
