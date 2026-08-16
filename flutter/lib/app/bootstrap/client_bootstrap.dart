import 'dart:async';

import 'package:argus/app/platform/platform_host.dart';
import 'package:argus/core/bridge/bridge.dart';
import 'package:argus/core/client/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'client_bootstrap.g.dart';

/// Host-supplied standard application-data directory for production startup.
///
/// Desktop production leaves this null and uses the existing platform
/// defaults; Android app composition supplies the app-private root from the
/// latched platform runtime configuration before the client is created.
@Riverpod(keepAlive: true)
String? standardApplicationDataDirectory(Ref ref) => null;

/// Optional mounted-volume capability supplied by production app composition.
/// Desktop and tests leave this null, preserving the existing gateway call
/// sequence without platform discovery.
@Riverpod(keepAlive: true)
LocalFilesystemPlatformApi? localFilesystemPlatformApi(Ref ref) => null;

/// Creates a fresh bridge adapter for each root-client generation.
@Riverpod(keepAlive: true)
ArgusClientGateway Function() argusClientGatewayFactory(Ref ref) {
  final standardDirectory = ref.watch(standardApplicationDataDirectoryProvider);
  final localFilesystem = ref.watch(localFilesystemPlatformApiProvider);
  return () => FrbArgusClientGateway(
    standardApplicationDataDirectory: standardDirectory,
    mountedVolumesReader: localFilesystem == null
        ? null
        : () async {
            final volumes = await localFilesystem.readMountedVolumes();
            return volumes
                .map(
                  (volume) => MountedLocalFilesystemVolumeFact(
                    providerVolumeId: volume.providerVolumeId,
                    transientMountPath: volume.transientMountPath,
                    safeDisplayName: volume.safeDisplayName,
                    isPrimary: volume.isPrimary,
                    isRemovable: volume.isRemovable,
                  ),
                )
                .toList(growable: false);
          },
  );
}

/// App-lifetime owner of the single active root [ArgusClient].
///
/// Replacement follows this order: construct the replacement inert client,
/// retire/dispose the previous client (cancelling its native subscription),
/// then publish the replacement. This preserves exactly one active root
/// client and one native runtime-event connection.
@Riverpod(keepAlive: true)
class ArgusClientHost extends _$ArgusClientHost {
  ClientFailure? _retirementFailure;
  ArgusClient? _ownedClient;

  @override
  ArgusClient build() {
    final client = ArgusClient(
      gateway: ref.watch(argusClientGatewayFactoryProvider)(),
    );
    _ownedClient = client;
    ref.onDispose(() {
      // Dispose whichever client is current at application teardown, not the
      // client captured when the host was first built.
      final current = _ownedClient;
      if (current != null) {
        unawaited(current.dispose());
      }
    });
    return client;
  }

  /// Replaces the active root client with a fresh inert client.
  Future<ArgusClient> replace() async {
    final unresolved = _retirementFailure;
    if (unresolved != null) {
      // A failed retirement is never silently bypassed: publishing another
      // client could leave two native event connections alive.
      throw unresolved;
    }
    final previous = state;
    final next = ArgusClient(
      gateway: ref.read(argusClientGatewayFactoryProvider)(),
    );
    try {
      await previous.dispose();
    } catch (error, stackTrace) {
      final typed = TransportFailure(
        'Previous root client could not be retired',
        cause: error,
        stackTrace: stackTrace,
      );
      _retirementFailure = typed;
      throw typed;
    }
    state = next;
    _ownedClient = next;
    return next;
  }

  /// The currently published active root client.
  ArgusClient get current => state;
}

/// Provides the single active root client for focused API composition.
@Riverpod(keepAlive: true)
ArgusClient argusClient(Ref ref) => ref.watch(argusClientHostProvider);

/// Focused runtime capability consumed by startup and recovery.
@Riverpod(keepAlive: true)
RuntimeApi runtimeApi(Ref ref) => ref.watch(argusClientProvider).runtime;

/// Focused failed-startup diagnostics capability.
@Riverpod(keepAlive: true)
DiagnosticsApi diagnosticsApi(Ref ref) =>
    ref.watch(argusClientProvider).diagnostics;

/// Shared mapped runtime notification projection.
@Riverpod(keepAlive: true)
EventsApi runtimeEvents(Ref ref) => ref.watch(argusClientProvider).events;

/// Initialization-only client seam.
///
/// The first call initializes the active root client. Later calls replace the
/// root client through [ArgusClientHost] before initializing, so every call
/// is a fresh bootstrap attempt without reusing a partially initialized
/// client or gateway.
@Riverpod(keepAlive: true)
ClientBootstrap clientBootstrap(Ref ref) => _AppClientBootstrap(ref);

final class _AppClientBootstrap implements ClientBootstrap {
  _AppClientBootstrap(this._ref);

  final Ref _ref;
  bool _hasBootstrapped = false;
  Future<RuntimeState>? _inFlight;

  @override
  Future<RuntimeState> initialize() {
    return _inFlight ??= _initialize().whenComplete(() {
      _inFlight = null;
    });
  }

  Future<RuntimeState> _initialize() async {
    final host = _ref.read(argusClientHostProvider.notifier);
    final client = _hasBootstrapped ? await host.replace() : host.current;
    _hasBootstrapped = true;
    return client.initialize();
  }
}
