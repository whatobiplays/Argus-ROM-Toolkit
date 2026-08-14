// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'appearance_settings_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One application-lifetime owner of frontend appearance state.
///
/// The outer [AsyncValue] represents whether usable appearance authority
/// exists: loading until the first authoritative read completes, error when
/// that initial read fails, and data with separated confirmed/presented
/// semantics afterwards. A loaded last-known snapshot remains renderable
/// across runtime replacement; only a successful authoritative read changes
/// [AppearanceSettingsState.confirmed].

@ProviderFor(AppearanceSettingsController)
final appearanceSettingsControllerProvider =
    AppearanceSettingsControllerProvider._();

/// One application-lifetime owner of frontend appearance state.
///
/// The outer [AsyncValue] represents whether usable appearance authority
/// exists: loading until the first authoritative read completes, error when
/// that initial read fails, and data with separated confirmed/presented
/// semantics afterwards. A loaded last-known snapshot remains renderable
/// across runtime replacement; only a successful authoritative read changes
/// [AppearanceSettingsState.confirmed].
final class AppearanceSettingsControllerProvider
    extends
        $NotifierProvider<
          AppearanceSettingsController,
          AsyncValue<AppearanceSettingsState>
        > {
  /// One application-lifetime owner of frontend appearance state.
  ///
  /// The outer [AsyncValue] represents whether usable appearance authority
  /// exists: loading until the first authoritative read completes, error when
  /// that initial read fails, and data with separated confirmed/presented
  /// semantics afterwards. A loaded last-known snapshot remains renderable
  /// across runtime replacement; only a successful authoritative read changes
  /// [AppearanceSettingsState.confirmed].
  AppearanceSettingsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appearanceSettingsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appearanceSettingsControllerHash();

  @$internal
  @override
  AppearanceSettingsController create() => AppearanceSettingsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<AppearanceSettingsState> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<AppearanceSettingsState>>(
        value,
      ),
    );
  }
}

String _$appearanceSettingsControllerHash() =>
    r'5db7510c081f6c006b9cfb511953af79e937b646';

/// One application-lifetime owner of frontend appearance state.
///
/// The outer [AsyncValue] represents whether usable appearance authority
/// exists: loading until the first authoritative read completes, error when
/// that initial read fails, and data with separated confirmed/presented
/// semantics afterwards. A loaded last-known snapshot remains renderable
/// across runtime replacement; only a successful authoritative read changes
/// [AppearanceSettingsState.confirmed].

abstract class _$AppearanceSettingsController
    extends $Notifier<AsyncValue<AppearanceSettingsState>> {
  AsyncValue<AppearanceSettingsState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<AppearanceSettingsState>,
              AsyncValue<AppearanceSettingsState>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<AppearanceSettingsState>,
                AsyncValue<AppearanceSettingsState>
              >,
              AsyncValue<AppearanceSettingsState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
