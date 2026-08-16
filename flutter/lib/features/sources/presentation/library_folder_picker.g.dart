// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_folder_picker.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provides the native folder picker used by the add workflow.

@ProviderFor(libraryFolderPicker)
final libraryFolderPickerProvider = LibraryFolderPickerProvider._();

/// Provides the native folder picker used by the add workflow.

final class LibraryFolderPickerProvider
    extends
        $FunctionalProvider<
          LibraryFolderPicker,
          LibraryFolderPicker,
          LibraryFolderPicker
        >
    with $Provider<LibraryFolderPicker> {
  /// Provides the native folder picker used by the add workflow.
  LibraryFolderPickerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryFolderPickerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryFolderPickerHash();

  @$internal
  @override
  $ProviderElement<LibraryFolderPicker> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LibraryFolderPicker create(Ref ref) {
    return libraryFolderPicker(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LibraryFolderPicker value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LibraryFolderPicker>(value),
    );
  }
}

String _$libraryFolderPickerHash() =>
    r'b8b2c9de643a7effeefa4ae27763c3a47f3d1834';
