// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'foreground_execution_coordinator.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Creates the one app-lifetime coordinator over the root client's focused
/// capabilities. Desktop composition supplies no host and remains pass-through.

@ProviderFor(foregroundExecutionCoordinator)
final foregroundExecutionCoordinatorProvider =
    ForegroundExecutionCoordinatorProvider._();

/// Creates the one app-lifetime coordinator over the root client's focused
/// capabilities. Desktop composition supplies no host and remains pass-through.

final class ForegroundExecutionCoordinatorProvider
    extends
        $FunctionalProvider<
          ForegroundExecutionCoordinator,
          ForegroundExecutionCoordinator,
          ForegroundExecutionCoordinator
        >
    with $Provider<ForegroundExecutionCoordinator> {
  /// Creates the one app-lifetime coordinator over the root client's focused
  /// capabilities. Desktop composition supplies no host and remains pass-through.
  ForegroundExecutionCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'foregroundExecutionCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$foregroundExecutionCoordinatorHash();

  @$internal
  @override
  $ProviderElement<ForegroundExecutionCoordinator> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ForegroundExecutionCoordinator create(Ref ref) {
    return foregroundExecutionCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ForegroundExecutionCoordinator value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ForegroundExecutionCoordinator>(
        value,
      ),
    );
  }
}

String _$foregroundExecutionCoordinatorHash() =>
    r'9f7547f45272ebd0dc51fc1a596d35fb280eea0a';
