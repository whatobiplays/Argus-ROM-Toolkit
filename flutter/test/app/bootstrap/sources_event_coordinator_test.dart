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

  test('source-changed payloads produce exact scoped demands', () async {
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
      _event(
        const RuntimeEventPayload.sourceEntriesChanged(
          libraryRootId: LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
          scope: SourceEntriesChangeScope.rootChildren(),
        ),
        BigInt.one,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    controller.add(
      _event(
        const RuntimeEventPayload.sourceEntriesChanged(
          libraryRootId: LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
          scope: SourceEntriesChangeScope.entryChildren(
            parentSourceEntryId: SourceEntryId(
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            ),
          ),
        ),
        BigInt.two,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    controller.add(
      _event(
        const RuntimeEventPayload.sourceEntriesChanged(
          libraryRootId: LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
          scope: SourceEntriesChangeScope.entireRootHierarchy(),
        ),
        BigInt.from(3),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(demands, <SourcesReconciliationDemand>[
      const SourcesReconciliationDemand.sourceChanged(
        libraryRootId: LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
        scope: SourceEntriesChangeScope.rootChildren(),
      ),
      const SourcesReconciliationDemand.sourceChanged(
        libraryRootId: LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
        scope: SourceEntriesChangeScope.entryChildren(
          parentSourceEntryId: SourceEntryId(
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          ),
        ),
      ),
      const SourcesReconciliationDemand.sourceChanged(
        libraryRootId: LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
        scope: SourceEntriesChangeScope.entireRootHierarchy(),
      ),
    ]);
    await controller.close();
  });

  test(
    'sequence gaps after source events broaden to entire-root demands',
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
        _event(
          const RuntimeEventPayload.sourceEntriesChanged(
            libraryRootId: LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
            scope: SourceEntriesChangeScope.entryChildren(
              parentSourceEntryId: SourceEntryId(
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              ),
            ),
          ),
          BigInt.one,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      controller.add(
        _event(
          const RuntimeEventPayload.appearanceSettingsChanged(),
          BigInt.from(9),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(demands, <SourcesReconciliationDemand>[
        const SourcesReconciliationDemand.sourceChanged(
          libraryRootId: LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
          scope: SourceEntriesChangeScope.entryChildren(
            parentSourceEntryId: SourceEntryId(
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            ),
          ),
        ),
        const SourcesReconciliationDemand.rootsChanged(),
        const SourcesReconciliationDemand.sourceChanged(
          libraryRootId: LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
          scope: SourceEntriesChangeScope.entireRootHierarchy(),
        ),
      ]);

      controller.addError(const TransportFailure('stream broken'));
      await Future<void>.delayed(Duration.zero);
      expect(demands.length, 5);
      expect(
        demands[4],
        const SourcesReconciliationDemand.sourceChanged(
          libraryRootId: LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
          scope: SourceEntriesChangeScope.entireRootHierarchy(),
        ),
      );
      await controller.close();
    },
  );

  test(
    'a source event for one root does not invalidate another root',
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
        _event(
          const RuntimeEventPayload.sourceEntriesChanged(
            libraryRootId: LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
            scope: SourceEntriesChangeScope.entryChildren(
              parentSourceEntryId: SourceEntryId(
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              ),
            ),
          ),
          BigInt.one,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      controller.add(
        _event(
          const RuntimeEventPayload.sourceEntriesChanged(
            libraryRootId: LibraryRootId('cccccccccccccccccccccccccccccccc'),
            scope: SourceEntriesChangeScope.entryChildren(
              parentSourceEntryId: SourceEntryId(
                'dddddddddddddddddddddddddddddddd',
              ),
            ),
          ),
          BigInt.two,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      controller.add(
        _event(
          const RuntimeEventPayload.appearanceSettingsChanged(),
          BigInt.from(9),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final sourceDemands = demands
          .whereType<SourcesReconciliationDemandSourceChanged>()
          .toList();
      expect(sourceDemands.map((demand) => demand.libraryRootId).toSet(), {
        const LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
        const LibraryRootId('cccccccccccccccccccccccccccccccc'),
      });
      expect(
        sourceDemands
            .where(
              (demand) => demand.scope is SourceEntriesChangeScopeEntryChildren,
            )
            .length,
        2,
      );
      expect(
        sourceDemands
            .where(
              (demand) =>
                  demand.scope is SourceEntriesChangeScopeEntireRootHierarchy,
            )
            .length,
        2,
      );
      await controller.close();
    },
  );

  test(
    'runtime generation change resets tracked roots and sequence state',
    () async {
      final controller = StreamController<RuntimeEvent>.broadcast();
      final runtimeState =
          NotifierProvider<RuntimeIdHolder, RuntimeInstanceId?>(
            RuntimeIdHolder.new,
          );
      final container = ProviderContainer(
        overrides: [
          readyRuntimeInstanceIdProvider.overrideWith(
            (ref) => ref.watch(runtimeState),
          ),
          runtimeEventsProvider.overrideWithValue(
            _StreamEventsApi(controller.stream),
          ),
          sourcesReconciliationDemandProvider.overrideWith(
            (ref) => ref.watch(sourcesEventCoordinatorProvider),
          ),
        ],
      );
      addTearDown(container.dispose);
      final firstDemands = <SourcesReconciliationDemand>[];
      final firstSubscription = container
          .read(sourcesReconciliationDemandProvider)
          .stream
          .listen(firstDemands.add);
      addTearDown(firstSubscription.cancel);

      controller.add(
        _event(
          const RuntimeEventPayload.sourceEntriesChanged(
            libraryRootId: LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
            scope: SourceEntriesChangeScope.entryChildren(
              parentSourceEntryId: SourceEntryId(
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              ),
            ),
          ),
          BigInt.one,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(firstDemands, hasLength(1));

      final replacement = RuntimeInstanceId('fedcba9876543210fedcba9876543210');
      container.read(runtimeState.notifier).replace(replacement);
      await Future<void>.delayed(Duration.zero);

      final secondDemands = <SourcesReconciliationDemand>[];
      final secondSubscription = container
          .read(sourcesReconciliationDemandProvider)
          .stream
          .listen(secondDemands.add);
      addTearDown(secondSubscription.cancel);

      controller.add(
        RuntimeEvent(
          runtimeInstanceId: replacement,
          sequence: BigInt.one,
          occurredAtMs: BigInt.one,
          payload: const RuntimeEventPayload.sourceEntriesChanged(
            libraryRootId: LibraryRootId('cccccccccccccccccccccccccccccccc'),
            scope: SourceEntriesChangeScope.rootChildren(),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      controller.add(
        RuntimeEvent(
          runtimeInstanceId: replacement,
          sequence: BigInt.from(9),
          occurredAtMs: BigInt.one,
          payload: const RuntimeEventPayload.appearanceSettingsChanged(),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final broadDemands = secondDemands
          .whereType<SourcesReconciliationDemandSourceChanged>()
          .toList();
      expect(
        broadDemands.map((demand) => demand.libraryRootId).toSet(),
        {const LibraryRootId('cccccccccccccccccccccccccccccccc')},
        reason: 'old-domain tracked roots must not survive replacement',
      );
      await controller.close();
    },
  );
}

final class RuntimeIdHolder extends Notifier<RuntimeInstanceId?> {
  @override
  RuntimeInstanceId? build() => _runtimeId;

  void replace(RuntimeInstanceId value) {
    state = value;
  }
}

final class _StreamEventsApi implements EventsApi {
  _StreamEventsApi(this.stream);

  final Stream<RuntimeEvent> stream;

  @override
  Stream<RuntimeEvent> get events => stream;
}
