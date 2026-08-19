// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'foreground_execution_host_composition.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Optional app-composition foreground host; desktop and tests leave it null.

@ProviderFor(foregroundExecutionHostApi)
final foregroundExecutionHostApiProvider =
    ForegroundExecutionHostApiProvider._();

/// Optional app-composition foreground host; desktop and tests leave it null.

final class ForegroundExecutionHostApiProvider
    extends
        $FunctionalProvider<
          ForegroundExecutionHostApi?,
          ForegroundExecutionHostApi?,
          ForegroundExecutionHostApi?
        >
    with $Provider<ForegroundExecutionHostApi?> {
  /// Optional app-composition foreground host; desktop and tests leave it null.
  ForegroundExecutionHostApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'foregroundExecutionHostApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$foregroundExecutionHostApiHash();

  @$internal
  @override
  $ProviderElement<ForegroundExecutionHostApi?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ForegroundExecutionHostApi? create(Ref ref) {
    return foregroundExecutionHostApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ForegroundExecutionHostApi? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ForegroundExecutionHostApi?>(value),
    );
  }
}

String _$foregroundExecutionHostApiHash() =>
    r'eebec3f0fbe9d9619c726751788abea03d3f898c';
