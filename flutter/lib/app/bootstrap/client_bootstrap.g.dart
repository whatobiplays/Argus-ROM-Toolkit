// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_bootstrap.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Creates the native bridge adapter without starting runtime work. Slice 006
/// will decide when application startup consumes this composition seam.

@ProviderFor(argusClientGateway)
final argusClientGatewayProvider = ArgusClientGatewayProvider._();

/// Creates the native bridge adapter without starting runtime work. Slice 006
/// will decide when application startup consumes this composition seam.

final class ArgusClientGatewayProvider
    extends
        $FunctionalProvider<
          ArgusClientGateway,
          ArgusClientGateway,
          ArgusClientGateway
        >
    with $Provider<ArgusClientGateway> {
  /// Creates the native bridge adapter without starting runtime work. Slice 006
  /// will decide when application startup consumes this composition seam.
  ArgusClientGatewayProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'argusClientGatewayProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$argusClientGatewayHash();

  @$internal
  @override
  $ProviderElement<ArgusClientGateway> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ArgusClientGateway create(Ref ref) {
    return argusClientGateway(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ArgusClientGateway value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ArgusClientGateway>(value),
    );
  }
}

String _$argusClientGatewayHash() =>
    r'add6f63d8fcf11fdd9f3a4ae3ad49b0529f2f07f';

/// Creates the pure-Dart root client around the bridge adapter.

@ProviderFor(argusClient)
final argusClientProvider = ArgusClientProvider._();

/// Creates the pure-Dart root client around the bridge adapter.

final class ArgusClientProvider
    extends $FunctionalProvider<ArgusClient, ArgusClient, ArgusClient>
    with $Provider<ArgusClient> {
  /// Creates the pure-Dart root client around the bridge adapter.
  ArgusClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'argusClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$argusClientHash();

  @$internal
  @override
  $ProviderElement<ArgusClient> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ArgusClient create(Ref ref) {
    return argusClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ArgusClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ArgusClient>(value),
    );
  }
}

String _$argusClientHash() => r'0e6fd041003cccbba8b2070991cf1e876235cf6f';

/// Exposes the planned startup seam while keeping it unused by the current
/// production shell until the next governed slice.

@ProviderFor(clientBootstrap)
final clientBootstrapProvider = ClientBootstrapProvider._();

/// Exposes the planned startup seam while keeping it unused by the current
/// production shell until the next governed slice.

final class ClientBootstrapProvider
    extends
        $FunctionalProvider<ClientBootstrap, ClientBootstrap, ClientBootstrap>
    with $Provider<ClientBootstrap> {
  /// Exposes the planned startup seam while keeping it unused by the current
  /// production shell until the next governed slice.
  ClientBootstrapProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clientBootstrapProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clientBootstrapHash();

  @$internal
  @override
  $ProviderElement<ClientBootstrap> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ClientBootstrap create(Ref ref) {
    return clientBootstrap(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ClientBootstrap value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ClientBootstrap>(value),
    );
  }
}

String _$clientBootstrapHash() => r'0234ad0acc4d301b62c1c6346802c8e986cd38e8';
