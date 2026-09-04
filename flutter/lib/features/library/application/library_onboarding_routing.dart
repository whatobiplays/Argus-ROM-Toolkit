import 'package:argus/core/client/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../library_composition.dart';
import 'library_state.dart';

part 'library_onboarding_routing.g.dart';

/// The routing-safe lifecycle of the authoritative onboarding projection.
enum LibraryOnboardingRoutingStatus { preReady, required, complete }

/// Backend-authoritative onboarding state scoped to one runtime generation.
final class LibraryOnboardingRoutingState {
  const LibraryOnboardingRoutingState._({
    required this.status,
    required this.runtimeInstanceId,
  });

  /// Creates the state used until a ready runtime generation exists.
  const LibraryOnboardingRoutingState.preReady()
    : this._(
        status: LibraryOnboardingRoutingStatus.preReady,
        runtimeInstanceId: null,
      );

  /// Creates a state from an authoritative backend onboarding projection.
  const LibraryOnboardingRoutingState.authoritative({
    required RuntimeInstanceId runtimeInstanceId,
    required bool complete,
  }) : this._(
         status: complete
             ? LibraryOnboardingRoutingStatus.complete
             : LibraryOnboardingRoutingStatus.required,
         runtimeInstanceId: runtimeInstanceId,
       );

  /// Whether routing can admit onboarding or the normal application shell.
  final LibraryOnboardingRoutingStatus status;

  /// The runtime generation that produced this authoritative state.
  final RuntimeInstanceId? runtimeInstanceId;
}

/// Hydrates onboarding authority outside GoRouter redirect evaluation.
@Riverpod(keepAlive: true)
class LibraryOnboardingRouting extends _$LibraryOnboardingRouting {
  @override
  Future<LibraryOnboardingRoutingState> build() async {
    ref.listen<LibraryRuntimeContext>(libraryRuntimeContextProvider, (
      previous,
      next,
    ) {
      if (previous != null && previous != next) {
        state = const AsyncData(LibraryOnboardingRoutingState.preReady());
      }
    });
    final runtime = ref.watch(libraryRuntimeContextProvider);
    if (runtime case LibraryRuntimeContextPreReady()) {
      return const LibraryOnboardingRoutingState.preReady();
    }
    final runtimeInstanceId = switch (runtime) {
      LibraryRuntimeContextReady(:final runtimeInstanceId) => runtimeInstanceId,
      LibraryRuntimeContextPreReady() => throw StateError(
        'unreachable pre-ready state',
      ),
    };
    final authoritative = await ref
        .watch(libraryOnboardingApiProvider)
        .getState();
    return LibraryOnboardingRoutingState.authoritative(
      runtimeInstanceId: runtimeInstanceId,
      complete: authoritative.complete,
    );
  }

  /// Accepts a command/read result only when it belongs to the current
  /// ready runtime generation.
  void acceptAuthoritative({
    required RuntimeInstanceId runtimeInstanceId,
    required LibraryOnboardingState authoritative,
  }) {
    final runtime = ref.read(libraryRuntimeContextProvider);
    if (runtime case LibraryRuntimeContextReady(
      runtimeInstanceId: final currentRuntimeInstanceId,
    )) {
      if (currentRuntimeInstanceId != runtimeInstanceId) return;
      state = AsyncData(
        LibraryOnboardingRoutingState.authoritative(
          runtimeInstanceId: runtimeInstanceId,
          complete: authoritative.complete,
        ),
      );
    }
  }

  /// Retries the current generation's authoritative onboarding read.
  void retry() => ref.invalidateSelf();
}
