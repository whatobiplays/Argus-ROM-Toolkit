import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:argus/features/sources/application/source_entry_detail_controller.dart';
import 'package:argus/features/sources/application/source_hierarchy_controller.dart';
import 'package:argus/features/sources/application/source_hierarchy_state.dart';
import 'package:argus/features/sources/application/sources_state.dart';
import 'package:argus/features/sources/sources_composition.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sources_test_fakes.dart';

const _rootId = LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
const _runtimeId = RuntimeInstanceId('1234567890abcdef1234567890abcdef');
const _replacementRuntimeId = RuntimeInstanceId(
  'fedcba9876543210fedcba9876543210',
);

List<SourceEntry> numberedEntries(int count, {String prefix = 'e'}) => [
  for (var index = 0; index < count; index++)
    fakeEntry(
      id: (index + 1).toRadixString(16).padLeft(32, '0'),
      name: '$prefix${index + 1}',
      kind: SourceEntryKind.directory,
      classification: SourceEntryClassification.container,
    ),
];

ProviderContainer createContainer(
  FakeSourcesApi api, {
  Stream<SourcesReconciliationDemand>? demands,
  NotifierProvider<RuntimeContextHolder, SourcesRuntimeContext>? runtime,
}) {
  final container = ProviderContainer(
    overrides: [
      sourcesApiProvider.overrideWithValue(api),
      sourcesRuntimeContextProvider.overrideWith(
        runtime == null
            ? (ref) => const SourcesRuntimeContext.ready(
                runtimeInstanceId: _runtimeId,
              )
            : (ref) => ref.watch(runtime),
      ),
      sourcesReconciliationDemandProvider.overrideWith(
        (ref) => SourcesReconciliationDemandSource(
          demands ?? const Stream<SourcesReconciliationDemand>.empty(),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  // Keep the keepAlive hierarchy provider observed, matching real widget
  // listeners; Riverpod otherwise disposes an unobserved provider.
  final observation = container.listen<AsyncValue<SourceHierarchyState>>(
    sourceHierarchyControllerProvider(_rootId),
    (previous, next) {},
  );
  addTearDown(observation.close);
  return container;
}

Future<void> settle() async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<SourceHierarchyState> waitForState(
  ProviderContainer container,
  bool Function(SourceHierarchyState state) predicate,
) async {
  final current = container.read(sourceHierarchyControllerProvider(_rootId));
  final value = current.value;
  if (value != null && predicate(value)) return value;
  final completer = Completer<SourceHierarchyState>();
  final subscription = container.listen<AsyncValue<SourceHierarchyState>>(
    sourceHierarchyControllerProvider(_rootId),
    (previous, next) {
      final state = next.value;
      if (state != null && predicate(state) && !completer.isCompleted) {
        completer.complete(state);
      }
    },
  );
  addTearDown(subscription.close);
  return completer.future.timeout(const Duration(seconds: 5));
}

void main() {
  test('initial load fetches only the root first page', () async {
    final api = FakeSourcesApi()..childrenByParent[''] = numberedEntries(3);
    final container = createContainer(api);

    final state = await waitForState(
      container,
      (state) => state.scopesByParent['']?.hasLoaded == true,
    );

    expect(state.scopesByParent.keys, [''], reason: 'no eager descendant load');
    expect(state.scopesByParent['']!.children, hasLength(3));
    expect(state.expandedEntryIds, isEmpty);
    expect(state.selectedEntryId, isNull);
    expect(api.listChildrenCalls, 1);
  });

  test('expand loads only that parent direct children', () async {
    final dirA = fakeEntry(id: 'a' * 32, name: 'A');
    final dirB = fakeEntry(id: 'b' * 32, name: 'B');
    final api = FakeSourcesApi()
      ..childrenByParent[''] = [dirA, dirB]
      ..childrenByParent[dirA.sourceEntryId.value] = numberedEntries(
        2,
        prefix: 'c',
      )
      ..childrenByParent[dirB.sourceEntryId.value] = numberedEntries(
        1,
        prefix: 'd',
      );
    final container = createContainer(api);
    await waitForState(
      container,
      (state) => state.scopesByParent['']?.hasLoaded == true,
    );

    await container
        .read(sourceHierarchyControllerProvider(_rootId).notifier)
        .expand(_rootId, dirA.sourceEntryId);

    var state = container
        .read(sourceHierarchyControllerProvider(_rootId))
        .value!;
    expect(state.expandedEntryIds, {dirA.sourceEntryId.value});
    expect(
      state.scopesByParent[dirA.sourceEntryId.value]!.children,
      hasLength(2),
    );
    expect(state.scopesByParent.containsKey(dirB.sourceEntryId.value), isFalse);
    expect(api.listChildrenCalls, 2);

    await container
        .read(sourceHierarchyControllerProvider(_rootId).notifier)
        .expand(_rootId, dirB.sourceEntryId);
    state = container.read(sourceHierarchyControllerProvider(_rootId)).value!;
    expect(
      state.scopesByParent[dirB.sourceEntryId.value]!.children,
      hasLength(1),
    );
    expect(api.listChildrenCalls, 3);
  });

  test('per-parent next-page appends in backend order', () async {
    final api = FakeSourcesApi()..childrenByParent[''] = numberedEntries(105);
    final container = createContainer(api);
    await waitForState(
      container,
      (state) => state.scopesByParent['']?.hasLoaded == true,
    );
    final notifier = container.read(
      sourceHierarchyControllerProvider(_rootId).notifier,
    );

    var state = container
        .read(sourceHierarchyControllerProvider(_rootId))
        .value!;
    expect(state.scopesByParent['']!.children, hasLength(100));
    expect(state.scopesByParent['']!.nextCursor, '100');

    await notifier.loadMore(_rootId, '');
    state = container.read(sourceHierarchyControllerProvider(_rootId)).value!;
    expect(state.scopesByParent['']!.children, hasLength(105));
    expect(state.scopesByParent['']!.nextCursor, isNull);

    final calls = api.listChildrenCalls;
    await notifier.loadMore(_rootId, '');
    expect(api.listChildrenCalls, calls, reason: 'no request without cursor');
  });

  test(
    'scoped next-page failure preserves children and retry succeeds',
    () async {
      final api = FakeSourcesApi()..childrenByParent[''] = numberedEntries(105);
      final container = createContainer(api);
      await waitForState(
        container,
        (state) => state.scopesByParent['']?.hasLoaded == true,
      );
      final notifier = container.read(
        sourceHierarchyControllerProvider(_rootId).notifier,
      );

      api.listChildrenFailure = transportFailure();
      await notifier.loadMore(_rootId, '');
      var state = container
          .read(sourceHierarchyControllerProvider(_rootId))
          .value!;
      expect(state.scopesByParent['']!.children, hasLength(100));
      expect(state.scopesByParent['']!.failure, isA<TransportFailure>());

      await notifier.retry(_rootId, '');
      state = container.read(sourceHierarchyControllerProvider(_rootId)).value!;
      expect(state.scopesByParent['']!.children, hasLength(105));
      expect(state.scopesByParent['']!.failure, isNull);
    },
  );

  test(
    'first-page failure surfaces a scoped failure and retry reloads page one',
    () async {
      final api = FakeSourcesApi()..childrenByParent[''] = numberedEntries(3);
      api.listChildrenFailure = transportFailure();
      final container = createContainer(api);
      await settle();

      expect(
        container.read(sourceHierarchyControllerProvider(_rootId)),
        isA<AsyncError<SourceHierarchyState>>(),
      );
      await container
          .read(sourceHierarchyControllerProvider(_rootId).notifier)
          .refresh(_rootId);
      final state = container
          .read(sourceHierarchyControllerProvider(_rootId))
          .value!;
      expect(state.scopesByParent['']!.children, hasLength(3));
    },
  );

  test('lifecycle demand retries an initial root load after failure', () async {
    final api = FakeSourcesApi()..childrenByParent[''] = numberedEntries(3);
    api.listChildrenFailure = transportFailure();
    final demands = StreamController<SourcesReconciliationDemand>.broadcast();
    final container = createContainer(api, demands: demands.stream);
    await settle();

    expect(
      container.read(sourceHierarchyControllerProvider(_rootId)),
      isA<AsyncError<SourceHierarchyState>>(),
    );
    api.listChildrenFailure = null;
    demands.add(const SourcesReconciliationDemand.lifecycleChanged());

    final state = await waitForState(
      container,
      (value) => value.scopesByParent['']?.hasLoaded == true,
    );
    expect(state.scopesByParent['']!.children, hasLength(3));
    expect(api.listChildrenCalls, 2);
    await demands.close();
  });

  test(
    'exact invalidation scopes refresh only the reliable loaded scope',
    () async {
      final dirA = fakeEntry(id: 'a' * 32, name: 'A');
      final dirB = fakeEntry(id: 'b' * 32, name: 'B');
      final api = FakeSourcesApi()
        ..childrenByParent[''] = [dirA, dirB]
        ..childrenByParent[dirA.sourceEntryId.value] = numberedEntries(
          2,
          prefix: 'c',
        );
      final demands = StreamController<SourcesReconciliationDemand>.broadcast();
      final container = createContainer(api, demands: demands.stream);
      await waitForState(
        container,
        (state) => state.scopesByParent['']?.hasLoaded == true,
      );
      await container
          .read(sourceHierarchyControllerProvider(_rootId).notifier)
          .expand(_rootId, dirA.sourceEntryId);

      api.childrenByParent[''] = [
        dirA,
        dirB,
        fakeEntry(id: 'c' * 32, name: 'New'),
      ];
      demands.add(
        const SourcesReconciliationDemand.sourceChanged(
          libraryRootId: _rootId,
          scope: SourceEntriesChangeScope.rootChildren(),
        ),
      );
      await settle();
      var state = container
          .read(sourceHierarchyControllerProvider(_rootId))
          .value!;
      expect(state.scopesByParent['']!.children, hasLength(3));
      expect(
        state.scopesByParent[dirA.sourceEntryId.value]!.children,
        hasLength(2),
      );
      expect(api.listChildrenCalls, 3, reason: 'dir_a scope must not refresh');

      api.childrenByParent[dirA.sourceEntryId.value] = numberedEntries(
        3,
        prefix: 'c',
      );
      demands.add(
        SourcesReconciliationDemand.sourceChanged(
          libraryRootId: _rootId,
          scope: SourceEntriesChangeScope.entryChildren(
            parentSourceEntryId: dirA.sourceEntryId,
          ),
        ),
      );
      await settle();
      state = container.read(sourceHierarchyControllerProvider(_rootId)).value!;
      expect(
        state.scopesByParent[dirA.sourceEntryId.value]!.children,
        hasLength(3),
      );
      expect(api.listChildrenCalls, 4);

      demands.add(
        SourcesReconciliationDemand.sourceChanged(
          libraryRootId: _rootId,
          scope: SourceEntriesChangeScope.entryChildren(
            parentSourceEntryId: dirB.sourceEntryId,
          ),
        ),
      );
      await settle();
      expect(api.listChildrenCalls, 4, reason: 'unloaded scope ignored');

      demands.add(
        const SourcesReconciliationDemand.sourceChanged(
          libraryRootId: _rootId,
          scope: SourceEntriesChangeScope.entireRootHierarchy(),
        ),
      );
      await settle();
      expect(api.listChildrenCalls, 6, reason: 'both loaded scopes refreshed');
      await demands.close();
    },
  );

  test('broad refresh coalesces scoped demands while pending', () async {
    final dirA = fakeEntry(id: 'a' * 32, name: 'A');
    final api = FakeSourcesApi()
      ..childrenByParent[''] = [dirA]
      ..childrenByParent[dirA.sourceEntryId.value] = numberedEntries(2);
    final demands = StreamController<SourcesReconciliationDemand>.broadcast();
    final container = createContainer(api, demands: demands.stream);
    await waitForState(
      container,
      (state) => state.scopesByParent['']?.hasLoaded == true,
    );
    await container
        .read(sourceHierarchyControllerProvider(_rootId).notifier)
        .expand(_rootId, dirA.sourceEntryId);
    expect(api.listChildrenCalls, 2);

    final gate = Completer<void>();
    api.listChildrenGates.add(gate);
    api.listChildrenGates.add(gate);
    demands.add(
      const SourcesReconciliationDemand.sourceChanged(
        libraryRootId: _rootId,
        scope: SourceEntriesChangeScope.entireRootHierarchy(),
      ),
    );
    await settle();
    demands.add(
      SourcesReconciliationDemand.sourceChanged(
        libraryRootId: _rootId,
        scope: SourceEntriesChangeScope.entryChildren(
          parentSourceEntryId: dirA.sourceEntryId,
        ),
      ),
    );
    await settle();
    expect(
      api.listChildrenCalls,
      4,
      reason: 'scoped demand folds into broad refresh',
    );

    gate.complete();
    await settle();
    expect(api.listChildrenCalls, 4);
    await demands.close();
  });

  test(
    'lifecycle demand refreshes loaded scopes and retains drill-down state',
    () async {
      final dirA = fakeEntry(id: 'a' * 32, name: 'A');
      final api = FakeSourcesApi()
        ..childrenByParent[''] = [dirA]
        ..childrenByParent[dirA.sourceEntryId.value] = numberedEntries(1);
      final demands = StreamController<SourcesReconciliationDemand>.broadcast();
      final container = createContainer(api, demands: demands.stream);
      await waitForState(
        container,
        (state) => state.scopesByParent['']?.hasLoaded == true,
      );
      await container
          .read(sourceHierarchyControllerProvider(_rootId).notifier)
          .openContainer(_rootId, dirA.sourceEntryId);
      await waitForState(
        container,
        (state) =>
            state.scopesByParent[dirA.sourceEntryId.value]?.hasLoaded == true,
      );

      final replacement = fakeEntry(id: 'b' * 32, name: 'B');
      api.childrenByParent[''] = [dirA, replacement];
      api.childrenByParent[dirA.sourceEntryId.value] = numberedEntries(2);
      demands.add(const SourcesReconciliationDemand.lifecycleChanged());
      await settle();

      final state = container
          .read(sourceHierarchyControllerProvider(_rootId))
          .value!;
      expect(state.scopesByParent['']!.children, hasLength(2));
      expect(
        state.scopesByParent[dirA.sourceEntryId.value]!.children,
        hasLength(2),
      );
      expect(state.compactDrillDownPath, [dirA.sourceEntryId]);
      expect(api.listChildrenCalls, 4);
      await demands.close();
    },
  );

  test(
    'invalidated scope restarts at page one and replaces its cursor chain',
    () async {
      final api = FakeSourcesApi()..childrenByParent[''] = numberedEntries(105);
      final demands = StreamController<SourcesReconciliationDemand>.broadcast();
      final container = createContainer(api, demands: demands.stream);
      await waitForState(
        container,
        (state) => state.scopesByParent['']?.hasLoaded == true,
      );
      await container
          .read(sourceHierarchyControllerProvider(_rootId).notifier)
          .loadMore(_rootId, '');
      expect(
        container
            .read(sourceHierarchyControllerProvider(_rootId))
            .value!
            .scopesByParent['']!
            .children,
        hasLength(105),
      );

      api.childrenByParent[''] = numberedEntries(3, prefix: 'replacement');
      demands.add(
        const SourcesReconciliationDemand.sourceChanged(
          libraryRootId: _rootId,
          scope: SourceEntriesChangeScope.rootChildren(),
        ),
      );
      await settle();
      final state = container
          .read(sourceHierarchyControllerProvider(_rootId))
          .value!;
      expect(state.scopesByParent['']!.children, hasLength(3));
      expect(state.scopesByParent['']!.nextCursor, isNull);
      expect(
        state.scopesByParent['']!.children.first.displayName,
        'replacement1',
      );
      await demands.close();
    },
  );

  test(
    'runtime replacement reconciles all loaded scopes without events',
    () async {
      final dirA = fakeEntry(id: 'a' * 32, name: 'A');
      final api = FakeSourcesApi()
        ..childrenByParent[''] = [dirA]
        ..childrenByParent[dirA.sourceEntryId.value] = numberedEntries(2);
      final runtime =
          NotifierProvider<RuntimeContextHolder, SourcesRuntimeContext>(
            RuntimeContextHolder.new,
          );
      final container = createContainer(api, runtime: runtime);
      await waitForState(
        container,
        (state) => state.scopesByParent['']?.hasLoaded == true,
      );
      await container
          .read(sourceHierarchyControllerProvider(_rootId).notifier)
          .expand(_rootId, dirA.sourceEntryId);
      expect(api.listChildrenCalls, 2);

      final contextChanges = <SourcesRuntimeContext>[];
      container.listen<SourcesRuntimeContext>(
        sourcesRuntimeContextProvider,
        (previous, next) => contextChanges.add(next),
      );
      container.read(runtime.notifier).replace(_replacementRuntimeId);
      await settle();

      expect(api.listChildrenCalls, 4, reason: 'both loaded scopes re-queried');
      final state = container
          .read(sourceHierarchyControllerProvider(_rootId))
          .value!;
      expect(state.scopesByParent['']!.children, hasLength(1));
      expect(
        state.scopesByParent[dirA.sourceEntryId.value]!.children,
        hasLength(2),
      );
      expect(state.reconciling, isFalse);
    },
  );

  test('stale async results from the old generation cannot publish', () async {
    final api = FakeSourcesApi()..childrenByParent[''] = numberedEntries(3);
    final demands = StreamController<SourcesReconciliationDemand>.broadcast();
    final runtime =
        NotifierProvider<RuntimeContextHolder, SourcesRuntimeContext>(
          RuntimeContextHolder.new,
        );
    final container = createContainer(
      api,
      demands: demands.stream,
      runtime: runtime,
    );
    await waitForState(
      container,
      (state) => state.scopesByParent['']?.hasLoaded == true,
    );

    final oldRefreshGate = Completer<void>();
    final newRefreshGate = Completer<void>();
    api.listChildrenGates.add(oldRefreshGate);
    api.listChildrenGates.add(newRefreshGate);
    demands.add(
      const SourcesReconciliationDemand.sourceChanged(
        libraryRootId: _rootId,
        scope: SourceEntriesChangeScope.rootChildren(),
      ),
    );
    await settle();

    api.childrenByParent[''] = numberedEntries(2, prefix: 'new');
    container.read(runtime.notifier).replace(_replacementRuntimeId);
    await settle();
    newRefreshGate.complete();
    await settle();
    final afterNew = container
        .read(sourceHierarchyControllerProvider(_rootId))
        .value!;
    expect(afterNew.scopesByParent['']!.children, hasLength(2));

    oldRefreshGate.complete();
    await settle();
    final afterOld = container
        .read(sourceHierarchyControllerProvider(_rootId))
        .value!;
    expect(
      afterOld.scopesByParent['']!.children.map((entry) => entry.displayName),
      ['new1', 'new2'],
      reason: 'stale old-generation page must not overwrite confirmed state',
    );
    expect(afterOld.scopesByParent['']!.refreshing, isFalse);
    await demands.close();
  });

  test(
    'broad refresh publishes both scopes when the root completes first',
    () async {
      final dirA = fakeEntry(
        id: 'a' * 32,
        name: 'A',
        kind: SourceEntryKind.directory,
        classification: SourceEntryClassification.container,
      );
      final api = FakeSourcesApi()
        ..childrenByParent[''] = [dirA]
        ..childrenByParent[dirA.sourceEntryId.value] = [
          fakeEntry(id: 'c' * 32, name: 'C'),
        ];
      final demands = StreamController<SourcesReconciliationDemand>.broadcast();
      final container = createContainer(api, demands: demands.stream);
      await waitForState(
        container,
        (state) => state.scopesByParent['']?.hasLoaded == true,
      );
      await container
          .read(sourceHierarchyControllerProvider(_rootId).notifier)
          .expand(_rootId, dirA.sourceEntryId);
      expect(api.listChildrenCalls, 2);

      api.childrenByParent[''] = [dirA, fakeEntry(id: 'd' * 32, name: 'D')];
      api.childrenByParent[dirA.sourceEntryId.value] = [
        fakeEntry(id: 'c' * 32, name: 'C'),
        fakeEntry(id: 'e' * 32, name: 'E'),
      ];
      final rootGate = Completer<void>();
      final childGate = Completer<void>();
      api.listChildrenGates
        ..add(rootGate)
        ..add(childGate);
      demands.add(
        const SourcesReconciliationDemand.sourceChanged(
          libraryRootId: _rootId,
          scope: SourceEntriesChangeScope.entireRootHierarchy(),
        ),
      );
      await settle();
      expect(
        api.listChildrenCalls,
        4,
        reason: 'both scopes refresh concurrently',
      );

      rootGate.complete();
      await settle();
      var state = container
          .read(sourceHierarchyControllerProvider(_rootId))
          .value!;
      expect(
        state.scopesByParent['']!.children.map((entry) => entry.displayName),
        ['A', 'D'],
      );
      expect(
        state.scopesByParent[dirA.sourceEntryId.value]!.children,
        hasLength(1),
        reason: 'child scope is still in flight and keeps confirmed content',
      );

      childGate.complete();
      await settle();
      state = container.read(sourceHierarchyControllerProvider(_rootId)).value!;
      expect(
        state.scopesByParent[dirA.sourceEntryId.value]!.children.map(
          (entry) => entry.displayName,
        ),
        ['C', 'E'],
        reason: 'child snapshot publishes even though the root completed first',
      );
      await demands.close();
    },
  );

  test(
    'broad refresh publishes both scopes when the child completes first',
    () async {
      final dirA = fakeEntry(
        id: 'a' * 32,
        name: 'A',
        kind: SourceEntryKind.directory,
        classification: SourceEntryClassification.container,
      );
      final api = FakeSourcesApi()
        ..childrenByParent[''] = [dirA]
        ..childrenByParent[dirA.sourceEntryId.value] = [
          fakeEntry(id: 'c' * 32, name: 'C'),
        ];
      final demands = StreamController<SourcesReconciliationDemand>.broadcast();
      final container = createContainer(api, demands: demands.stream);
      await waitForState(
        container,
        (state) => state.scopesByParent['']?.hasLoaded == true,
      );
      await container
          .read(sourceHierarchyControllerProvider(_rootId).notifier)
          .expand(_rootId, dirA.sourceEntryId);

      api.childrenByParent[''] = [dirA, fakeEntry(id: 'd' * 32, name: 'D')];
      api.childrenByParent[dirA.sourceEntryId.value] = [
        fakeEntry(id: 'c' * 32, name: 'C'),
        fakeEntry(id: 'e' * 32, name: 'E'),
      ];
      final rootGate = Completer<void>();
      final childGate = Completer<void>();
      api.listChildrenGates
        ..add(rootGate)
        ..add(childGate);
      demands.add(
        const SourcesReconciliationDemand.sourceChanged(
          libraryRootId: _rootId,
          scope: SourceEntriesChangeScope.entireRootHierarchy(),
        ),
      );
      await settle();

      childGate.complete();
      await settle();
      var state = container
          .read(sourceHierarchyControllerProvider(_rootId))
          .value!;
      expect(
        state.scopesByParent[dirA.sourceEntryId.value]!.children.map(
          (entry) => entry.displayName,
        ),
        ['C', 'E'],
      );
      expect(
        state.scopesByParent['']!.children,
        hasLength(1),
        reason: 'root scope is still in flight and keeps confirmed content',
      );

      rootGate.complete();
      await settle();
      state = container.read(sourceHierarchyControllerProvider(_rootId)).value!;
      expect(
        state.scopesByParent['']!.children.map((entry) => entry.displayName),
        ['A', 'D'],
      );
      await demands.close();
    },
  );

  test(
    'runtime replacement updates multiple loaded scopes independently',
    () async {
      final dirA = fakeEntry(
        id: 'a' * 32,
        name: 'A',
        kind: SourceEntryKind.directory,
        classification: SourceEntryClassification.container,
      );
      final api = FakeSourcesApi()
        ..childrenByParent[''] = [dirA]
        ..childrenByParent[dirA.sourceEntryId.value] = [
          fakeEntry(id: 'c' * 32, name: 'C'),
        ];
      final runtime =
          NotifierProvider<RuntimeContextHolder, SourcesRuntimeContext>(
            RuntimeContextHolder.new,
          );
      final container = createContainer(api, runtime: runtime);
      await waitForState(
        container,
        (state) => state.scopesByParent['']?.hasLoaded == true,
      );
      await container
          .read(sourceHierarchyControllerProvider(_rootId).notifier)
          .expand(_rootId, dirA.sourceEntryId);
      expect(api.listChildrenCalls, 2);

      api.childrenByParent[''] = [dirA, fakeEntry(id: 'd' * 32, name: 'D')];
      api.childrenByParent[dirA.sourceEntryId.value] = [
        fakeEntry(id: 'c' * 32, name: 'C'),
        fakeEntry(id: 'e' * 32, name: 'E'),
      ];
      final rootGate = Completer<void>();
      final childGate = Completer<void>();
      api.listChildrenGates
        ..add(rootGate)
        ..add(childGate);
      container.read(runtime.notifier).replace(_replacementRuntimeId);
      await settle();
      expect(
        api.listChildrenCalls,
        4,
        reason: 'broad refresh after replacement',
      );

      childGate.complete();
      await settle();
      var state = container
          .read(sourceHierarchyControllerProvider(_rootId))
          .value!;
      expect(
        state.scopesByParent[dirA.sourceEntryId.value]!.children.map(
          (entry) => entry.displayName,
        ),
        ['C', 'E'],
        reason: 'new-generation child snapshot publishes independently',
      );
      expect(
        state.scopesByParent['']!.children,
        hasLength(1),
        reason: 'root refresh is still in flight under the same new generation',
      );

      rootGate.complete();
      await settle();
      state = container.read(sourceHierarchyControllerProvider(_rootId)).value!;
      expect(
        state.scopesByParent['']!.children.map((entry) => entry.displayName),
        ['A', 'D'],
        reason: 'both scopes carry new-generation authoritative data',
      );
    },
  );

  test(
    'same-parent page-one refresh supersedes an obsolete loadMore',
    () async {
      final api = FakeSourcesApi()..childrenByParent[''] = numberedEntries(105);
      final demands = StreamController<SourcesReconciliationDemand>.broadcast();
      final container = createContainer(api, demands: demands.stream);
      await waitForState(
        container,
        (state) => state.scopesByParent['']?.hasLoaded == true,
      );
      expect(api.listChildrenCalls, 1);
      final notifier = container.read(
        sourceHierarchyControllerProvider(_rootId).notifier,
      );

      final loadMoreGate = Completer<void>();
      final refreshGate = Completer<void>();
      api.listChildrenGates
        ..add(loadMoreGate)
        ..add(refreshGate);
      api.listChildrenScripted.add(
        SourceEntryChildrenPage(
          items: [
            fakeEntry(id: 'g' * 32, name: 'new1'),
            fakeEntry(id: 'h' * 32, name: 'new2'),
          ],
          nextCursor: null,
        ),
      );
      api.listChildrenScripted.add(
        SourceEntryChildrenPage(
          items: [fakeEntry(id: 'f' * 32, name: 'old-tail')],
          nextCursor: null,
        ),
      );

      final loadMoreFuture = notifier.loadMore(_rootId, '');
      await settle();
      expect(api.listChildrenCalls, 2);
      demands.add(
        const SourcesReconciliationDemand.sourceChanged(
          libraryRootId: _rootId,
          scope: SourceEntriesChangeScope.rootChildren(),
        ),
      );
      await settle();
      expect(
        api.listChildrenCalls,
        3,
        reason: 'refresh starts while loadMore is pending',
      );

      refreshGate.complete();
      await settle();
      var state = container
          .read(sourceHierarchyControllerProvider(_rootId))
          .value!;
      expect(
        state.scopesByParent['']!.children.map((entry) => entry.displayName),
        ['new1', 'new2'],
      );

      loadMoreGate.complete();
      await loadMoreFuture;
      await settle();
      state = container.read(sourceHierarchyControllerProvider(_rootId)).value!;
      expect(
        state.scopesByParent['']!.children.map((entry) => entry.displayName),
        ['new1', 'new2'],
        reason:
            'obsolete cursor append must not overwrite the refreshed snapshot',
      );
      expect(state.scopesByParent['']!.loadingMore, isFalse);
      await demands.close();
    },
  );

  test('independent parent refreshes do not invalidate each other', () async {
    final dirA = fakeEntry(
      id: 'a' * 32,
      name: 'A',
      kind: SourceEntryKind.directory,
      classification: SourceEntryClassification.container,
    );
    final dirB = fakeEntry(
      id: 'b' * 32,
      name: 'B',
      kind: SourceEntryKind.directory,
      classification: SourceEntryClassification.container,
    );
    final api = FakeSourcesApi()
      ..childrenByParent[''] = [dirA, dirB]
      ..childrenByParent[dirA.sourceEntryId.value] = [
        fakeEntry(id: 'c' * 32, name: 'C'),
      ]
      ..childrenByParent[dirB.sourceEntryId.value] = [
        fakeEntry(id: 'd' * 32, name: 'D'),
      ];
    final demands = StreamController<SourcesReconciliationDemand>.broadcast();
    final container = createContainer(api, demands: demands.stream);
    await waitForState(
      container,
      (state) => state.scopesByParent['']?.hasLoaded == true,
    );
    final notifier = container.read(
      sourceHierarchyControllerProvider(_rootId).notifier,
    );
    await notifier.expand(_rootId, dirA.sourceEntryId);
    await notifier.expand(_rootId, dirB.sourceEntryId);
    expect(api.listChildrenCalls, 3);

    api.childrenByParent[dirA.sourceEntryId.value] = [
      fakeEntry(id: 'c' * 32, name: 'C'),
      fakeEntry(id: 'e' * 32, name: 'E'),
    ];
    api.childrenByParent[dirB.sourceEntryId.value] = [
      fakeEntry(id: 'd' * 32, name: 'D'),
      fakeEntry(id: 'f' * 32, name: 'F'),
    ];
    final rootGate = Completer<void>();
    final gateA = Completer<void>();
    final gateB = Completer<void>();
    api.listChildrenGates
      ..add(rootGate)
      ..add(gateA)
      ..add(gateB);
    demands.add(
      const SourcesReconciliationDemand.sourceChanged(
        libraryRootId: _rootId,
        scope: SourceEntriesChangeScope.entireRootHierarchy(),
      ),
    );
    await settle();
    expect(api.listChildrenCalls, 6);

    gateB.complete();
    await settle();
    var state = container
        .read(sourceHierarchyControllerProvider(_rootId))
        .value!;
    expect(
      state.scopesByParent[dirB.sourceEntryId.value]!.children.map(
        (entry) => entry.displayName,
      ),
      ['D', 'F'],
    );
    expect(
      state.scopesByParent[dirA.sourceEntryId.value]!.children,
      hasLength(1),
      reason: 'completing B must not stale the in-flight A request',
    );

    gateA.complete();
    await settle();
    state = container.read(sourceHierarchyControllerProvider(_rootId)).value!;
    expect(
      state.scopesByParent[dirA.sourceEntryId.value]!.children.map(
        (entry) => entry.displayName,
      ),
      ['C', 'E'],
      reason: 'A publishes its authoritative snapshot after B completed',
    );

    rootGate.complete();
    await settle();
    state = container.read(sourceHierarchyControllerProvider(_rootId)).value!;
    expect(state.scopesByParent['']!.children, hasLength(2));
    await demands.close();
  });

  test('moved identities survive refresh even beyond page one', () async {
    final entry = fakeEntry(
      id: 'e' * 32,
      name: 'Moved',
      kind: SourceEntryKind.directory,
      classification: SourceEntryClassification.container,
    );
    final api = FakeSourcesApi()
      ..childrenByParent[''] = [entry]
      ..childrenByParent[entry.sourceEntryId.value] = numberedEntries(
        1,
        prefix: 'child',
      )
      ..detailsByEntry[entry.sourceEntryId.value] = fakeDetail(
        id: entry.sourceEntryId.value,
        name: 'Moved',
        kind: SourceEntryKind.directory,
        classification: SourceEntryClassification.container,
      );
    final demands = StreamController<SourcesReconciliationDemand>.broadcast();
    final container = createContainer(api, demands: demands.stream);
    await waitForState(
      container,
      (state) => state.scopesByParent['']?.hasLoaded == true,
    );
    final notifier = container.read(
      sourceHierarchyControllerProvider(_rootId).notifier,
    );
    await notifier.select(_rootId, entry.sourceEntryId);
    await notifier.openContainer(_rootId, entry.sourceEntryId);

    api.childrenByParent[''] = [fakeEntry(id: 'a' * 32, name: 'Other')];
    demands.add(
      const SourcesReconciliationDemand.sourceChanged(
        libraryRootId: _rootId,
        scope: SourceEntriesChangeScope.rootChildren(),
      ),
    );
    await settle();

    final state = container
        .read(sourceHierarchyControllerProvider(_rootId))
        .value!;
    expect(
      state.selectedEntryId,
      entry.sourceEntryId,
      reason: 'existence is proven by focused getSourceEntry, not page absence',
    );
    expect(state.expandedEntryIds, contains(entry.sourceEntryId.value));
    expect(state.compactDrillDownPath, [entry.sourceEntryId]);
    await demands.close();
  });

  test(
    'authoritative removal clears selection, expansion, and retreats path',
    () async {
      final ancestor = fakeEntry(id: 'a' * 32, name: 'A');
      final entry = fakeEntry(
        id: 'e' * 32,
        name: 'E',
        kind: SourceEntryKind.directory,
        classification: SourceEntryClassification.container,
      );
      final api = FakeSourcesApi()
        ..childrenByParent[''] = [ancestor, entry]
        ..childrenByParent[entry.sourceEntryId.value] = numberedEntries(
          1,
          prefix: 'child',
        );
      final demands = StreamController<SourcesReconciliationDemand>.broadcast();
      final container = createContainer(api, demands: demands.stream);
      await waitForState(
        container,
        (state) => state.scopesByParent['']?.hasLoaded == true,
      );
      final notifier = container.read(
        sourceHierarchyControllerProvider(_rootId).notifier,
      );
      await notifier.openContainer(_rootId, ancestor.sourceEntryId);
      await notifier.openContainer(_rootId, entry.sourceEntryId);
      await notifier.select(_rootId, entry.sourceEntryId);

      api.childrenByParent[''] = [ancestor];
      demands.add(
        const SourcesReconciliationDemand.sourceChanged(
          libraryRootId: _rootId,
          scope: SourceEntriesChangeScope.entireRootHierarchy(),
        ),
      );
      await settle();

      final state = container
          .read(sourceHierarchyControllerProvider(_rootId))
          .value!;
      expect(state.selectedEntryId, isNull);
      expect(
        state.expandedEntryIds,
        isNot(contains(entry.sourceEntryId.value)),
      );
      expect(
        state.compactDrillDownPath,
        [ancestor.sourceEntryId],
        reason: 'retreat to nearest valid ancestor only after proof of removal',
      );
      await demands.close();
    },
  );

  test('validation runs in bounded batches until the queue drains', () async {
    final rootEntry = fakeEntry(id: 'r' * 32, name: 'Root');
    final expanded = numberedEntries(10, prefix: 'c');
    final api = FakeSourcesApi()
      ..childrenByParent[''] = [rootEntry]
      ..childrenByParent['c'] = const [];
    for (final entry in expanded) {
      api.childrenByParent[entry.sourceEntryId.value] = const [];
      api.detailsByEntry[entry.sourceEntryId.value] = fakeDetail(
        id: entry.sourceEntryId.value,
        name: entry.displayName,
      );
    }
    final demands = StreamController<SourcesReconciliationDemand>.broadcast();
    final container = createContainer(api, demands: demands.stream);
    await waitForState(
      container,
      (state) => state.scopesByParent['']?.hasLoaded == true,
    );
    final notifier = container.read(
      sourceHierarchyControllerProvider(_rootId).notifier,
    );
    for (final entry in expanded) {
      await notifier.expand(_rootId, entry.sourceEntryId);
    }
    expect(api.getEntryCalls, 0, reason: 'validation runs on refresh only');

    demands.add(
      const SourcesReconciliationDemand.sourceChanged(
        libraryRootId: _rootId,
        scope: SourceEntriesChangeScope.rootChildren(),
      ),
    );
    await settle();

    expect(
      api.getEntryCalls,
      10,
      reason: 'queue drains without any additional backend event',
    );
    expect(
      api.maxGetDetailInFlight,
      lessThanOrEqualTo(
        SourceHierarchyController.maxTransientValidationsPerReconcile,
      ),
      reason: 'per-batch bound is enforced',
    );
    final state = container
        .read(sourceHierarchyControllerProvider(_rootId))
        .value!;
    expect(state.expandedEntryIds, hasLength(10));
    await demands.close();
  });

  test(
    'non-not-found validation failure preserves the transient identity',
    () async {
      final entry = fakeEntry(id: 'e' * 32, name: 'E');
      final api = FakeSourcesApi()
        ..childrenByParent[''] = [fakeEntry(id: 'a' * 32, name: 'A')]
        ..detailsByEntry[entry.sourceEntryId.value] = fakeDetail(
          id: entry.sourceEntryId.value,
          name: 'E',
        );
      api.getDetailFailure = transportFailure();
      final demands = StreamController<SourcesReconciliationDemand>.broadcast();
      final container = createContainer(api, demands: demands.stream);
      await waitForState(
        container,
        (state) => state.scopesByParent['']?.hasLoaded == true,
      );
      await container
          .read(sourceHierarchyControllerProvider(_rootId).notifier)
          .select(_rootId, entry.sourceEntryId);

      demands.add(
        const SourcesReconciliationDemand.sourceChanged(
          libraryRootId: _rootId,
          scope: SourceEntriesChangeScope.rootChildren(),
        ),
      );
      await settle();

      final state = container
          .read(sourceHierarchyControllerProvider(_rootId))
          .value!;
      expect(
        state.selectedEntryId,
        entry.sourceEntryId,
        reason: 'transport failure is not deletion evidence',
      );
      expect(api.getEntryCalls, 1, reason: 'no tight validation retry loop');
      await demands.close();
    },
  );

  test(
    'generation replacement prevents stale validation batches from publishing',
    () async {
      final entry = fakeEntry(id: 'e' * 32, name: 'E');
      final api = FakeSourcesApi()
        ..childrenByParent[''] = [fakeEntry(id: 'a' * 32, name: 'A')]
        ..detailsByEntry[entry.sourceEntryId.value] = fakeDetail(
          id: entry.sourceEntryId.value,
          name: 'E',
        );
      final demands = StreamController<SourcesReconciliationDemand>.broadcast();
      final runtime =
          NotifierProvider<RuntimeContextHolder, SourcesRuntimeContext>(
            RuntimeContextHolder.new,
          );
      final container = createContainer(
        api,
        demands: demands.stream,
        runtime: runtime,
      );
      await waitForState(
        container,
        (state) => state.scopesByParent['']?.hasLoaded == true,
      );
      await container
          .read(sourceHierarchyControllerProvider(_rootId).notifier)
          .select(_rootId, entry.sourceEntryId);

      final oldGate = Completer<void>();
      final newGate = Completer<void>();
      api.getDetailGates.add(oldGate);
      api.getDetailGates.add(newGate);
      demands.add(
        const SourcesReconciliationDemand.sourceChanged(
          libraryRootId: _rootId,
          scope: SourceEntriesChangeScope.rootChildren(),
        ),
      );
      await settle();
      expect(
        api.getEntryCalls,
        1,
        reason: 'old-generation validation in flight',
      );

      container.read(runtime.notifier).replace(_replacementRuntimeId);
      await settle();
      // The new-generation validation resolves first while the entry exists.
      newGate.complete();
      await settle();
      // The stale old-generation validation then resolves as REMOVED after the
      // entry was deleted from the fake. Its verdict must never publish.
      api.detailsByEntry.remove(entry.sourceEntryId.value);
      oldGate.complete();
      await settle();

      final state = container
          .read(sourceHierarchyControllerProvider(_rootId))
          .value!;
      expect(
        state.selectedEntryId,
        entry.sourceEntryId,
        reason:
            'stale removed verdict from the old generation must not publish',
      );
      expect(api.getEntryCalls, 2);
      await demands.close();
    },
  );

  test(
    'selected-entry detail refreshes only on source invalidation for its root',
    () async {
      const entry = SourceEntryId('eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee');
      final api = FakeSourcesApi()
        ..detailsByEntry[entry.value] = fakeDetail(
          id: entry.value,
          name: 'first',
        );
      final demands = StreamController<SourcesReconciliationDemand>.broadcast();
      final container = createContainer(api, demands: demands.stream);

      final first = await container.read(
        sourceEntryDetailControllerProvider(
          rootId: _rootId,
          sourceEntryId: entry,
        ).future,
      );
      expect(first.displayName, 'first');
      expect(api.getEntryCalls, 1);

      api.detailsByEntry[entry.value] = fakeDetail(
        id: entry.value,
        name: 'second',
      );
      demands.add(
        const SourcesReconciliationDemand.sourceChanged(
          libraryRootId: LibraryRootId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
          scope: SourceEntriesChangeScope.rootChildren(),
        ),
      );
      await settle();
      expect(
        api.getEntryCalls,
        1,
        reason: 'other-root invalidation is ignored',
      );

      demands.add(
        const SourcesReconciliationDemand.sourceChanged(
          libraryRootId: _rootId,
          scope: SourceEntriesChangeScope.rootChildren(),
        ),
      );
      await settle();
      final second = await container.read(
        sourceEntryDetailControllerProvider(
          rootId: _rootId,
          sourceEntryId: entry,
        ).future,
      );
      expect(second.displayName, 'second');
      expect(api.getEntryCalls, 2);
      await demands.close();
    },
  );

  test(
    'selected-entry detail refreshes after app lifecycle reconciliation',
    () async {
      const entry = SourceEntryId('ffffffffffffffffffffffffffffffff');
      final api = FakeSourcesApi()
        ..detailsByEntry[entry.value] = fakeDetail(
          id: entry.value,
          name: 'first',
        );
      final demands = StreamController<SourcesReconciliationDemand>.broadcast();
      final container = createContainer(api, demands: demands.stream);

      final provider = sourceEntryDetailControllerProvider(
        rootId: _rootId,
        sourceEntryId: entry,
      );
      await container.read(provider.future);
      expect(api.getEntryCalls, 1);

      api.detailsByEntry[entry.value] = fakeDetail(
        id: entry.value,
        name: 'second',
      );
      demands.add(const SourcesReconciliationDemand.lifecycleChanged());
      await settle();

      final refreshed = await container.read(provider.future);
      expect(refreshed.displayName, 'second');
      expect(api.getEntryCalls, 2);
      await demands.close();
    },
  );
}

final class RuntimeContextHolder extends Notifier<SourcesRuntimeContext> {
  @override
  SourcesRuntimeContext build() =>
      const SourcesRuntimeContext.ready(runtimeInstanceId: _runtimeId);

  void replace(RuntimeInstanceId runtimeInstanceId) {
    state = SourcesRuntimeContext.ready(runtimeInstanceId: runtimeInstanceId);
  }
}
