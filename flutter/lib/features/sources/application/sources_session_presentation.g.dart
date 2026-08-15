// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sources_session_presentation.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Session-only owner of the explicit root-sidebar preference.
///
/// `none` means the adaptive default applies; an explicit choice wins until a
/// fresh Flutter application/provider scope is created. This state is never
/// persisted.

@ProviderFor(SourcesSidebarPreference)
final sourcesSidebarPreferenceProvider = SourcesSidebarPreferenceProvider._();

/// Session-only owner of the explicit root-sidebar preference.
///
/// `none` means the adaptive default applies; an explicit choice wins until a
/// fresh Flutter application/provider scope is created. This state is never
/// persisted.
final class SourcesSidebarPreferenceProvider
    extends
        $NotifierProvider<SourcesSidebarPreference, SourcesSidebarOverride> {
  /// Session-only owner of the explicit root-sidebar preference.
  ///
  /// `none` means the adaptive default applies; an explicit choice wins until a
  /// fresh Flutter application/provider scope is created. This state is never
  /// persisted.
  SourcesSidebarPreferenceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sourcesSidebarPreferenceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sourcesSidebarPreferenceHash();

  @$internal
  @override
  SourcesSidebarPreference create() => SourcesSidebarPreference();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SourcesSidebarOverride value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SourcesSidebarOverride>(value),
    );
  }
}

String _$sourcesSidebarPreferenceHash() =>
    r'5532f53159ceee90a402c63062410dd0afb9834d';

/// Session-only owner of the explicit root-sidebar preference.
///
/// `none` means the adaptive default applies; an explicit choice wins until a
/// fresh Flutter application/provider scope is created. This state is never
/// persisted.

abstract class _$SourcesSidebarPreference
    extends $Notifier<SourcesSidebarOverride> {
  SourcesSidebarOverride build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<SourcesSidebarOverride, SourcesSidebarOverride>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SourcesSidebarOverride, SourcesSidebarOverride>,
              SourcesSidebarOverride,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
