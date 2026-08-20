import 'package:flutter/services.dart';

import '../application/diagnostics_publication_api.dart';

/// Android MethodChannel adapter for the scoped diagnostics share sheet.
///
/// The channel accepts no path or URI. Android resolves the one stable
/// backend/platform-relative artifact contract from its app-private data root,
/// validates only publication-boundary facts, and keeps the content URI inside
/// the native share flow.
final class MethodChannelAndroidDiagnosticsPublicationApi
    implements DiagnosticsPublicationApi {
  const MethodChannelAndroidDiagnosticsPublicationApi({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('argus/diagnostics_share');

  final MethodChannel _channel;

  @override
  Future<void> publishCompletedStartupDiagnostics() async {
    try {
      await _channel.invokeMethod<void>('shareCompletedStartupDiagnostics');
    } on PlatformException catch (error) {
      throw DiagnosticsPublicationException(_failureKind(error.code));
    } on MissingPluginException {
      throw const DiagnosticsPublicationException(
        DiagnosticsPublicationFailureKind.shareUnavailable,
      );
    }
  }

  DiagnosticsPublicationFailureKind _failureKind(String code) => switch (code) {
    'ARTIFACT_UNAVAILABLE' =>
      DiagnosticsPublicationFailureKind.artifactUnavailable,
    'ACTIVITY_UNAVAILABLE' =>
      DiagnosticsPublicationFailureKind.activityUnavailable,
    'PROVIDER_UNAVAILABLE' =>
      DiagnosticsPublicationFailureKind.providerUnavailable,
    _ => DiagnosticsPublicationFailureKind.shareUnavailable,
  };
}
