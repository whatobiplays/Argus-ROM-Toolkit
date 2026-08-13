import 'models.dart';

/// Distinguishable native/transport failure classes.
enum TransportFailureKind {
  bridgeUnavailable,
  communicationFailed,
  serializationFailed,
  contractMismatch,
  unexpectedTransportFailure,
}

/// Base class for failures returned by the framework-independent client.
sealed class ClientFailure implements Exception {
  const ClientFailure(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => message;
}

/// A request completed at the application boundary with a typed failure.
final class ApplicationFailure extends ClientFailure {
  ApplicationFailure(this.error, {super.cause, super.stackTrace})
    : super('Application operation failed: ${error.code}');

  final ClientApplicationError error;
}

/// Native bridge/event transport failed. It is intentionally distinct from
/// application failures and is emitted on the event stream's error channel.
final class TransportFailure extends ClientFailure {
  const TransportFailure(
    super.message, {
    this.kind = TransportFailureKind.unexpectedTransportFailure,
    super.cause,
    super.stackTrace,
  });

  final TransportFailureKind kind;
}
