import 'package:flutter/services.dart';

/// Debug-only Android controls used by the repository-owned qualification
/// harness.
///
/// The native implementation is deliberately unavailable in release builds.
/// These methods expose test evidence and deterministic host-failure controls;
/// they are not a product lifecycle or execution authority.
final class AndroidQualificationApi {
  const AndroidQualificationApi({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  final MethodChannel _channel;

  /// Returns the opaque identity of the currently attached Android Activity.
  Future<String> readActivityInstanceId() async {
    final value = await _channel.invokeMethod<Object?>(
      'readActivityInstanceId',
    );
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Android Activity identity is invalid');
    }
    return value;
  }

  /// Makes the next execution-host service admission fail once.
  Future<void> rejectNextExecutionHostStart() {
    return _channel.invokeMethod<void>('rejectNextExecutionHostStart');
  }

  /// Invokes the native service timeout callback and reports whether it ran.
  Future<bool> triggerExecutionHostTimeout() async {
    final value = await _channel.invokeMethod<Object?>(
      'triggerExecutionHostTimeout',
    );
    return value is bool ? value : false;
  }

  /// Invokes the native unexpected-destruction callback and reports whether it ran.
  Future<bool> triggerExecutionHostLoss() async {
    final value = await _channel.invokeMethod<Object?>(
      'triggerExecutionHostLoss',
    );
    return value is bool ? value : false;
  }

  static const _channelName = 'argus/android_qualification';
}
