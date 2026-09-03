import 'package:flutter/services.dart';

import '../application/macos_library_folder_picker_api.dart';

/// macOS MethodChannel adapter for the native security-scoped folder picker.
///
/// The native side returns a path for presentation and an opaque byte payload
/// for the Rust provider. This adapter validates only the transport shape and
/// never interprets the authorization bytes.
final class MethodChannelMacosLibraryFolderPickerApi
    implements MacosLibraryFolderPickerApi {
  const MethodChannelMacosLibraryFolderPickerApi({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('argus/macos_library_folder_picker');

  final MethodChannel _channel;

  @override
  Future<MacosLibraryFolderSelection?> pickLibraryFolder() async {
    final Object? raw;
    try {
      raw = await _channel.invokeMethod<Object?>('pickLibraryFolder');
    } on PlatformException {
      throw const MacosLibraryFolderPickerException(
        MacosLibraryFolderPickerFailureKind.nativeUnavailable,
      );
    } on MissingPluginException {
      throw const MacosLibraryFolderPickerException(
        MacosLibraryFolderPickerFailureKind.nativeUnavailable,
      );
    }
    if (raw == null) return null;
    if (raw is! Map<Object?, Object?>) {
      throw const MacosLibraryFolderPickerException(
        MacosLibraryFolderPickerFailureKind.malformedResponse,
      );
    }
    final path = raw['path'];
    final authorization = raw['authorization'];
    if (path is! String ||
        path.isEmpty ||
        authorization is! Uint8List ||
        authorization.isEmpty) {
      throw const MacosLibraryFolderPickerException(
        MacosLibraryFolderPickerFailureKind.malformedResponse,
      );
    }
    return MacosLibraryFolderSelection(
      path: path,
      authorization: authorization,
    );
  }
}
