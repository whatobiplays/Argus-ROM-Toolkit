// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_onboarding_routing.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Hydrates onboarding authority outside GoRouter redirect evaluation.

@ProviderFor(LibraryOnboardingRouting)
final libraryOnboardingRoutingProvider = LibraryOnboardingRoutingProvider._();

/// Hydrates onboarding authority outside GoRouter redirect evaluation.
final class LibraryOnboardingRoutingProvider
    extends
        $AsyncNotifierProvider<
          LibraryOnboardingRouting,
          LibraryOnboardingRoutingState
        > {
  /// Hydrates onboarding authority outside GoRouter redirect evaluation.
  LibraryOnboardingRoutingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryOnboardingRoutingProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryOnboardingRoutingHash();

  @$internal
  @override
  LibraryOnboardingRouting create() => LibraryOnboardingRouting();
}

String _$libraryOnboardingRoutingHash() =>
    r'bfb01ea1da97eb2dae8630ae180ec1a2cfed7815';

/// Hydrates onboarding authority outside GoRouter redirect evaluation.

abstract class _$LibraryOnboardingRouting
    extends $AsyncNotifier<LibraryOnboardingRoutingState> {
  FutureOr<LibraryOnboardingRoutingState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<LibraryOnboardingRoutingState>,
              LibraryOnboardingRoutingState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<LibraryOnboardingRoutingState>,
                LibraryOnboardingRoutingState
              >,
              AsyncValue<LibraryOnboardingRoutingState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
