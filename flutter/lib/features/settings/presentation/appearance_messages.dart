import 'package:argus/core/client/client.dart';

/// User-safe copy for an initial appearance load failure.
///
/// Never renders raw backend text, exception text, or trace text.
String appearanceLoadFailureMessage(ClientFailure failure) => switch (failure) {
  TransportFailure() =>
    'Argus could not reach its runtime to load appearance settings.',
  ApplicationFailure() => 'Argus could not load appearance settings.',
};

/// User-safe copy for a failed or ambiguous appearance save.
String appearanceSaveFailureMessage(ClientFailure failure) => switch (failure) {
  TransportFailure() => 'Argus could not confirm the appearance change.',
  ApplicationFailure() => 'Argus could not save the appearance setting.',
};

/// Durable copy shown while the displayed selection cannot be confirmed.
const String appearanceUncertainMessage =
    'Argus could not confirm the current appearance setting. The displayed '
    'selection is the last known value.';
