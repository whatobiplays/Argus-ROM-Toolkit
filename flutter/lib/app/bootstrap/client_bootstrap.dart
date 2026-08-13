import 'package:argus/core/bridge/bridge.dart';
import 'package:argus/core/client/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'client_bootstrap.g.dart';

/// Creates the native bridge adapter without starting runtime work. Slice 006
/// will decide when application startup consumes this composition seam.
@Riverpod(keepAlive: true)
ArgusClientGateway argusClientGateway(Ref ref) => FrbArgusClientGateway();

/// Creates the pure-Dart root client around the bridge adapter.
@Riverpod(keepAlive: true)
ArgusClient argusClient(Ref ref) =>
    ArgusClient(gateway: ref.watch(argusClientGatewayProvider));

/// Exposes the planned startup seam while keeping it unused by the current
/// production shell until the next governed slice.
@Riverpod(keepAlive: true)
ClientBootstrap clientBootstrap(Ref ref) => ref.watch(argusClientProvider);
