import 'dart:async';

import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/app/bootstrap/sources_event_coordinator.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/sources/sources.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _runtimeId = RuntimeInstanceId('1234567890abcdef1234567890abcdef');

RuntimeEvent _event(RuntimeEventPayload payload, BigInt sequence) =>
    RuntimeEvent(
      runtimeInstanceId: _runtimeId,
      sequence: sequence,
      occurredAtMs: BigInt.one,
      payload: payload,
    );

void main() {
  test(
    'roots-changed and root-changed payloads produce narrow demands',
    () async {
      final controller = StreamController<RuntimeEvent>.broadcast();
      final container = ProviderContainer(
        overrides: [
          readyRuntimeInstanceIdProvider.overrideWithValue(_runtimeId),
          runtimeEventsProvider.overrideWithValue(
            _StreamEventsApi(controller.stream),
          ),
          sourcesReconciliationDemandProvider.overrideWith(
            (ref) => ref.watch(sourcesEventCoordinatorProvider),
          ),
        ],
      );
      addTearDown(container.dispose);
      final demands = <SourcesReconciliationDemand>[];
      final subscription = container
          .read(sourcesReconciliationDemandProvider)
          .stream
          .listen(demands.add);
      addTearDown(subscription.cancel);

      controller.add(
        _event(const RuntimeEventPayload.libraryRootsChanged(), BigInt.one),
      );
      await Future<void>.delayed(Duration.zero);
      controller.add(
        _event(
          const RuntimeEventPayload.libraryRootChanged(
            libraryRootId: LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
          ),
          BigInt.two,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(demands, <SourcesReconciliationDemand>[
        const SourcesReconciliationDemand.rootsChanged(),
        const SourcesReconciliationDemand.rootChanged(
          libraryRootId: LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
        ),
      ]);
      await controller.close();
    },
  );

  test('sequence gaps and stream failure broaden to roots-changed', () async {
    final controller = StreamController<RuntimeEvent>.broadcast();
    final container = ProviderContainer(
      overrides: [
        readyRuntimeInstanceIdProvider.overrideWithValue(_runtimeId),
        runtimeEventsProvider.overrideWithValue(
          _StreamEventsApi(controller.stream),
        ),
        sourcesReconciliationDemandProvider.overrideWith(
          (ref) => ref.watch(sourcesEventCoordinatorProvider),
        ),
      ],
    );
    addTearDown(container.dispose);
    final demands = <SourcesReconciliationDemand>[];
    final subscription = container
        .read(sourcesReconciliationDemandProvider)
        .stream
        .listen(demands.add);
    addTearDown(subscription.cancel);

    controller.add(
      _event(const RuntimeEventPayload.libraryRootsChanged(), BigInt.one),
    );
    await Future<void>.delayed(Duration.zero);
    // A forward gap must demand an authoritative refresh even though the
    // observed payload is unrelated to Sources.
    controller.add(
      _event(
        const RuntimeEventPayload.appearanceSettingsChanged(),
        BigInt.from(9),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(demands.length, 2);
    expect(demands[0], const SourcesReconciliationDemand.rootsChanged());
    expect(demands[1], const SourcesReconciliationDemand.rootsChanged());

    controller.addError(const TransportFailure('stream broken'));
    await Future<void>.delayed(Duration.zero);
    expect(demands.length, 3);
    await controller.close();
  });

  test(
    'other generations are ignored until the ready domain changes',
    () async {
      final controller = StreamController<RuntimeEvent>.broadcast();
      final container = ProviderContainer(
        overrides: [
          readyRuntimeInstanceIdProvider.overrideWithValue(_runtimeId),
          runtimeEventsProvider.overrideWithValue(
            _StreamEventsApi(controller.stream),
          ),
          sourcesReconciliationDemandProvider.overrideWith(
            (ref) => ref.watch(sourcesEventCoordinatorProvider),
          ),
        ],
      );
      addTearDown(container.dispose);
      final demands = <SourcesReconciliationDemand>[];
      final subscription = container
          .read(sourcesReconciliationDemandProvider)
          .stream
          .listen(demands.add);
      addTearDown(subscription.cancel);

      controller.add(
        RuntimeEvent(
          runtimeInstanceId: const RuntimeInstanceId(
            'ffffffffffffffffffffffffffffffff',
          ),
          sequence: BigInt.one,
          occurredAtMs: BigInt.one,
          payload: const RuntimeEventPayload.libraryRootsChanged(),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(demands, isEmpty);
      await controller.close();
    },
  );
}

final class _StreamEventsApi implements EventsApi {
  _StreamEventsApi(this.stream);

  final Stream<RuntimeEvent> stream;

  @override
  Stream<RuntimeEvent> get events => stream;
}
