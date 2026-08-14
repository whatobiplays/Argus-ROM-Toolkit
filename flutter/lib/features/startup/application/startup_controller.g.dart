// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'startup_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One application-lifetime owner of pre-ready startup and recovery state.
///
/// The controller consumes only the initialization-only [ClientBootstrap]
/// seam, [RuntimeApi], [DiagnosticsApi], and the shared mapped runtime-event
/// projection. It never imports FRB types, bridge DTOs, routing, Flutter, or
/// platform APIs, and it never infers readiness from time or events.

@ProviderFor(StartupController)
final startupControllerProvider = StartupControllerProvider._();

/// One application-lifetime owner of pre-ready startup and recovery state.
///
/// The controller consumes only the initialization-only [ClientBootstrap]
/// seam, [RuntimeApi], [DiagnosticsApi], and the shared mapped runtime-event
/// projection. It never imports FRB types, bridge DTOs, routing, Flutter, or
/// platform APIs, and it never infers readiness from time or events.
final class StartupControllerProvider
    extends $NotifierProvider<StartupController, AsyncValue<StartupState>> {
  /// One application-lifetime owner of pre-ready startup and recovery state.
  ///
  /// The controller consumes only the initialization-only [ClientBootstrap]
  /// seam, [RuntimeApi], [DiagnosticsApi], and the shared mapped runtime-event
  /// projection. It never imports FRB types, bridge DTOs, routing, Flutter, or
  /// platform APIs, and it never infers readiness from time or events.
  StartupControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'startupControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$startupControllerHash();

  @$internal
  @override
  StartupController create() => StartupController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<StartupState> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<StartupState>>(value),
    );
  }
}

String _$startupControllerHash() => r'acb4cbccf06ead5b63fd9da6479ec7f1930f4a77';

/// One application-lifetime owner of pre-ready startup and recovery state.
///
/// The controller consumes only the initialization-only [ClientBootstrap]
/// seam, [RuntimeApi], [DiagnosticsApi], and the shared mapped runtime-event
/// projection. It never imports FRB types, bridge DTOs, routing, Flutter, or
/// platform APIs, and it never infers readiness from time or events.

abstract class _$StartupController extends $Notifier<AsyncValue<StartupState>> {
  AsyncValue<StartupState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<StartupState>, AsyncValue<StartupState>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<StartupState>, AsyncValue<StartupState>>,
              AsyncValue<StartupState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
