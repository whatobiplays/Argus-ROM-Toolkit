import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/application/library_onboarding_routing.dart';
import 'package:argus/features/library/application/library_state.dart';
import 'package:argus/features/library/library_composition.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'library_test_fakes.dart';

const _runtimeA = RuntimeInstanceId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
const _runtimeB = RuntimeInstanceId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');

void main() {
  test('pre-ready runtime does not query onboarding authority', () async {
    final api = FakeLibraryOnboardingApi(_state(complete: false));
    final runtime = _runtimeProvider();
    final container = _createContainer(api, runtime);

    final state = await container.read(libraryOnboardingRoutingProvider.future);

    expect(state.status, LibraryOnboardingRoutingStatus.preReady);
    expect(state.runtimeInstanceId, isNull);
    expect(api.getStateCalls, 0);
  });

  test(
    'ready generation hydrates required state from backend authority',
    () async {
      final api = FakeLibraryOnboardingApi(_state(complete: false));
      final runtime = _runtimeProvider();
      final container = _createContainer(api, runtime);
      container
          .read(runtime.notifier)
          .replace(
            const LibraryRuntimeContext.ready(runtimeInstanceId: _runtimeA),
          );

      final state = await container.read(
        libraryOnboardingRoutingProvider.future,
      );

      expect(state.status, LibraryOnboardingRoutingStatus.required);
      expect(state.runtimeInstanceId, _runtimeA);
      expect(api.getStateCalls, 1);
    },
  );

  test(
    'authoritative completion result updates current generation immediately',
    () async {
      final api = FakeLibraryOnboardingApi(_state(complete: false));
      final runtime = _runtimeProvider();
      final container = _createContainer(api, runtime);
      container
          .read(runtime.notifier)
          .replace(
            const LibraryRuntimeContext.ready(runtimeInstanceId: _runtimeA),
          );
      await container.read(libraryOnboardingRoutingProvider.future);

      container
          .read(libraryOnboardingRoutingProvider.notifier)
          .acceptAuthoritative(
            runtimeInstanceId: _runtimeA,
            authoritative: _state(complete: true),
          );

      final state = container.read(libraryOnboardingRoutingProvider).value!;
      expect(state.status, LibraryOnboardingRoutingStatus.complete);
      expect(state.runtimeInstanceId, _runtimeA);
      expect(api.getStateCalls, 1);
    },
  );

  test(
    'runtime generation replacement discards projected completion and rehydrates',
    () async {
      final api = FakeLibraryOnboardingApi(_state(complete: false));
      final firstRead = Completer<LibraryOnboardingState>();
      final secondRead = Completer<LibraryOnboardingState>();
      api.getStateCompleter = firstRead;
      final runtime = _runtimeProvider();
      final container = _createContainer(api, runtime);
      container
          .read(runtime.notifier)
          .replace(
            const LibraryRuntimeContext.ready(runtimeInstanceId: _runtimeA),
          );
      await _settle();
      expect(api.getStateCalls, 1);

      firstRead.complete(_state(complete: false));
      await container.read(libraryOnboardingRoutingProvider.future);
      container
          .read(libraryOnboardingRoutingProvider.notifier)
          .acceptAuthoritative(
            runtimeInstanceId: _runtimeA,
            authoritative: _state(complete: true),
          );
      expect(
        container.read(libraryOnboardingRoutingProvider).value?.status,
        LibraryOnboardingRoutingStatus.complete,
      );

      api.getStateCompleter = secondRead;
      container
          .read(runtime.notifier)
          .replace(
            const LibraryRuntimeContext.ready(runtimeInstanceId: _runtimeB),
          );
      await _settle();

      final pending = container.read(libraryOnboardingRoutingProvider).value;
      expect(pending?.status, LibraryOnboardingRoutingStatus.preReady);
      expect(pending?.runtimeInstanceId, isNull);
      expect(api.getStateCalls, 2);

      secondRead.complete(_state(complete: false));
      final replacement = await container.read(
        libraryOnboardingRoutingProvider.future,
      );
      expect(replacement.status, LibraryOnboardingRoutingStatus.required);
      expect(replacement.runtimeInstanceId, _runtimeB);

      container
          .read(libraryOnboardingRoutingProvider.notifier)
          .acceptAuthoritative(
            runtimeInstanceId: _runtimeA,
            authoritative: _state(complete: true),
          );
      expect(
        container
            .read(libraryOnboardingRoutingProvider)
            .value
            ?.runtimeInstanceId,
        _runtimeB,
      );
      expect(
        container.read(libraryOnboardingRoutingProvider).value?.status,
        LibraryOnboardingRoutingStatus.required,
      );
    },
  );

  test(
    'failed authoritative read publishes AsyncError and retry re-queries',
    () async {
      final api = FakeLibraryOnboardingApi(_state(complete: true))
        ..getStateFailure = StateError('read failed');
      final runtime = _runtimeProvider();
      final container = _createContainer(api, runtime);
      container
          .read(runtime.notifier)
          .replace(
            const LibraryRuntimeContext.ready(runtimeInstanceId: _runtimeA),
          );

      await expectLater(
        container.read(libraryOnboardingRoutingProvider.future),
        throwsA(isA<StateError>()),
      );
      expect(container.read(libraryOnboardingRoutingProvider).hasError, isTrue);
      expect(api.getStateCalls, 1);

      api.getStateFailure = null;
      container.read(libraryOnboardingRoutingProvider.notifier).retry();
      final state = await container.read(
        libraryOnboardingRoutingProvider.future,
      );

      expect(state.status, LibraryOnboardingRoutingStatus.complete);
      expect(state.runtimeInstanceId, _runtimeA);
      expect(api.getStateCalls, 2);
    },
  );
}

ProviderContainer _createContainer(
  FakeLibraryOnboardingApi api,
  NotifierProvider<RoutingRuntimeContextHolder, LibraryRuntimeContext> runtime,
) {
  final container = ProviderContainer(
    overrides: [
      libraryOnboardingApiProvider.overrideWithValue(api),
      libraryRuntimeContextProvider.overrideWith((ref) => ref.watch(runtime)),
    ],
  );
  addTearDown(container.dispose);
  final observation = container
      .listen<AsyncValue<LibraryOnboardingRoutingState>>(
        libraryOnboardingRoutingProvider,
        (_, _) {},
        fireImmediately: true,
      );
  addTearDown(observation.close);
  return container;
}

NotifierProvider<RoutingRuntimeContextHolder, LibraryRuntimeContext>
_runtimeProvider() =>
    NotifierProvider<RoutingRuntimeContextHolder, LibraryRuntimeContext>(
      RoutingRuntimeContextHolder.new,
    );

Future<void> _settle() async {
  for (var index = 0; index < 20; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

LibraryOnboardingState _state({required bool complete}) =>
    LibraryOnboardingState(
      progress: LibraryOnboardingProgress(
        acceptedPrivacyTermsVersion: complete ? 'terms' : null,
        acceptedPrivacyAtMs: complete ? 1 : null,
        metadataPreferencesConfirmed: complete,
        providerSetupOutcome: complete
            ? LibraryProviderSetupOutcome.skipped
            : LibraryProviderSetupOutcome.pending,
        completedAtMs: complete ? 1 : null,
      ),
      requiredPrivacyTermsVersion: 'terms',
      requiresPrivacyAcceptance: !complete,
      requiresRootSelection: !complete,
      credentialConfigured: false,
      complete: complete,
    );

final class RoutingRuntimeContextHolder
    extends Notifier<LibraryRuntimeContext> {
  @override
  LibraryRuntimeContext build() => const LibraryRuntimeContext.preReady();

  void replace(LibraryRuntimeContext value) {
    state = value;
  }
}
