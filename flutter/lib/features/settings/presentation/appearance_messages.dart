import 'package:argus/core/client/client.dart';

/// User-safe copy for an initial appearance load failure.
///
/// Never renders raw backend text, exception text, or trace text.
String appearanceLoadFailureMessage(ClientFailure failure) => switch (failure) {
  TransportFailure() =>
    'Argus could not reach its runtime to load appearance settings.',
  ApplicationFailure() => 'Argus could not load appearance settings.',
};
