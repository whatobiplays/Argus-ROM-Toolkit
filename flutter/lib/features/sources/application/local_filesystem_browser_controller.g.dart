// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_filesystem_browser_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns browse navigation while retaining provider-issued identities and
/// cursors exactly as returned by the Sources API.

@ProviderFor(LocalFilesystemBrowserController)
final localFilesystemBrowserControllerProvider =
    LocalFilesystemBrowserControllerProvider._();

/// Owns browse navigation while retaining provider-issued identities and
/// cursors exactly as returned by the Sources API.
final class LocalFilesystemBrowserControllerProvider
    extends
        $NotifierProvider<
          LocalFilesystemBrowserController,
          LocalFilesystemBrowserState
        > {
  /// Owns browse navigation while retaining provider-issued identities and
  /// cursors exactly as returned by the Sources API.
  LocalFilesystemBrowserControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'localFilesystemBrowserControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$localFilesystemBrowserControllerHash();

  @$internal
  @override
  LocalFilesystemBrowserController create() =>
      LocalFilesystemBrowserController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LocalFilesystemBrowserState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LocalFilesystemBrowserState>(value),
    );
  }
}

String _$localFilesystemBrowserControllerHash() =>
    r'09b0d56276fb57bbca5d2d210bf84dbf81f1a68a';

/// Owns browse navigation while retaining provider-issued identities and
/// cursors exactly as returned by the Sources API.

abstract class _$LocalFilesystemBrowserController
    extends $Notifier<LocalFilesystemBrowserState> {
  LocalFilesystemBrowserState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<LocalFilesystemBrowserState, LocalFilesystemBrowserState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                LocalFilesystemBrowserState,
                LocalFilesystemBrowserState
              >,
              LocalFilesystemBrowserState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
