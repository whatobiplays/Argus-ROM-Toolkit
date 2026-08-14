// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_bootstrap.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Creates a fresh bridge adapter for each root-client generation.

@ProviderFor(argusClientGatewayFactory)
final argusClientGatewayFactoryProvider = ArgusClientGatewayFactoryProvider._();

/// Creates a fresh bridge adapter for each root-client generation.

final class ArgusClientGatewayFactoryProvider
    extends
        $FunctionalProvider<
          ArgusClientGateway Function(),
          ArgusClientGateway Function(),
          ArgusClientGateway Function()
        >
    with $Provider<ArgusClientGateway Function()> {
  /// Creates a fresh bridge adapter for each root-client generation.
  ArgusClientGatewayFactoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'argusClientGatewayFactoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$argusClientGatewayFactoryHash();

  @$internal
  @override
  $ProviderElement<ArgusClientGateway Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ArgusClientGateway Function() create(Ref ref) {
    return argusClientGatewayFactory(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ArgusClientGateway Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ArgusClientGateway Function()>(
        value,
      ),
    );
  }
}

String _$argusClientGatewayFactoryHash() =>
    r'17c756ae71b25d58d6009de1d82ce0084d6d4f04';

/// App-lifetime owner of the single active root [ArgusClient].
///
/// Replacement follows this order: construct the replacement inert client,
/// retire/dispose the previous client (cancelling its native subscription),
/// then publish the replacement. This preserves exactly one active root
/// client and one native runtime-event connection.

@ProviderFor(ArgusClientHost)
final argusClientHostProvider = ArgusClientHostProvider._();

/// App-lifetime owner of the single active root [ArgusClient].
///
/// Replacement follows this order: construct the replacement inert client,
/// retire/dispose the previous client (cancelling its native subscription),
/// then publish the replacement. This preserves exactly one active root
/// client and one native runtime-event connection.
final class ArgusClientHostProvider
    extends $NotifierProvider<ArgusClientHost, ArgusClient> {
  /// App-lifetime owner of the single active root [ArgusClient].
  ///
  /// Replacement follows this order: construct the replacement inert client,
  /// retire/dispose the previous client (cancelling its native subscription),
  /// then publish the replacement. This preserves exactly one active root
  /// client and one native runtime-event connection.
  ArgusClientHostProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'argusClientHostProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$argusClientHostHash();

  @$internal
  @override
  ArgusClientHost create() => ArgusClientHost();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ArgusClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ArgusClient>(value),
    );
  }
}

String _$argusClientHostHash() => r'97c1ccc3c50093caf7dfeccabf4a3e68db95fd5f';

/// App-lifetime owner of the single active root [ArgusClient].
///
/// Replacement follows this order: construct the replacement inert client,
/// retire/dispose the previous client (cancelling its native subscription),
/// then publish the replacement. This preserves exactly one active root
/// client and one native runtime-event connection.

abstract class _$ArgusClientHost extends $Notifier<ArgusClient> {
  ArgusClient build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ArgusClient, ArgusClient>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ArgusClient, ArgusClient>,
              ArgusClient,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Provides the single active root client for focused API composition.

@ProviderFor(argusClient)
final argusClientProvider = ArgusClientProvider._();

/// Provides the single active root client for focused API composition.

final class ArgusClientProvider
    extends $FunctionalProvider<ArgusClient, ArgusClient, ArgusClient>
    with $Provider<ArgusClient> {
  /// Provides the single active root client for focused API composition.
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

String _$argusClientHash() => r'09782f65a679752bbd6544a124224672407a5ae0';

/// Focused runtime capability consumed by startup and recovery.

@ProviderFor(runtimeApi)
final runtimeApiProvider = RuntimeApiProvider._();

/// Focused runtime capability consumed by startup and recovery.

final class RuntimeApiProvider
    extends $FunctionalProvider<RuntimeApi, RuntimeApi, RuntimeApi>
    with $Provider<RuntimeApi> {
  /// Focused runtime capability consumed by startup and recovery.
  RuntimeApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runtimeApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runtimeApiHash();

  @$internal
  @override
  $ProviderElement<RuntimeApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RuntimeApi create(Ref ref) {
    return runtimeApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RuntimeApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RuntimeApi>(value),
    );
  }
}

String _$runtimeApiHash() => r'a60c867e07e7d153a307d31125627d0ae60bdf33';

/// Focused failed-startup diagnostics capability.

@ProviderFor(diagnosticsApi)
final diagnosticsApiProvider = DiagnosticsApiProvider._();

/// Focused failed-startup diagnostics capability.

final class DiagnosticsApiProvider
    extends $FunctionalProvider<DiagnosticsApi, DiagnosticsApi, DiagnosticsApi>
    with $Provider<DiagnosticsApi> {
  /// Focused failed-startup diagnostics capability.
  DiagnosticsApiProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'diagnosticsApiProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$diagnosticsApiHash();

  @$internal
  @override
  $ProviderElement<DiagnosticsApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DiagnosticsApi create(Ref ref) {
    return diagnosticsApi(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DiagnosticsApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DiagnosticsApi>(value),
    );
  }
}

String _$diagnosticsApiHash() => r'6c7986bbe53dad71a49580204900bc6a13d294e1';

/// Shared mapped runtime notification projection.

@ProviderFor(runtimeEvents)
final runtimeEventsProvider = RuntimeEventsProvider._();

/// Shared mapped runtime notification projection.

final class RuntimeEventsProvider
    extends $FunctionalProvider<EventsApi, EventsApi, EventsApi>
    with $Provider<EventsApi> {
  /// Shared mapped runtime notification projection.
  RuntimeEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runtimeEventsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runtimeEventsHash();

  @$internal
  @override
  $ProviderElement<EventsApi> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  EventsApi create(Ref ref) {
    return runtimeEvents(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EventsApi value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EventsApi>(value),
    );
  }
}

String _$runtimeEventsHash() => r'24cc37e13591af11083821dfd371066eed85bbd4';

/// Initialization-only client seam.
///
/// The first call initializes the active root client. Later calls replace the
/// root client through [ArgusClientHost] before initializing, so every call
/// is a fresh bootstrap attempt without reusing a partially initialized
/// client or gateway.

@ProviderFor(clientBootstrap)
final clientBootstrapProvider = ClientBootstrapProvider._();

/// Initialization-only client seam.
///
/// The first call initializes the active root client. Later calls replace the
/// root client through [ArgusClientHost] before initializing, so every call
/// is a fresh bootstrap attempt without reusing a partially initialized
/// client or gateway.

final class ClientBootstrapProvider
    extends
        $FunctionalProvider<ClientBootstrap, ClientBootstrap, ClientBootstrap>
    with $Provider<ClientBootstrap> {
  /// Initialization-only client seam.
  ///
  /// The first call initializes the active root client. Later calls replace the
  /// root client through [ArgusClientHost] before initializing, so every call
  /// is a fresh bootstrap attempt without reusing a partially initialized
  /// client or gateway.
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

String _$clientBootstrapHash() => r'433edd4e5f5326b68573701aa06865e60463830a';
