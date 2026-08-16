import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:argus/core/design_system/argus_theme.dart';
import 'package:argus/features/sources/application/add_library_folder_controller.dart';
import 'package:argus/features/sources/application/root_detail_controller.dart';
import 'package:argus/features/sources/application/root_list_controller.dart';
import 'package:argus/features/sources/application/sources_session_presentation.dart';
import 'package:argus/features/sources/application/sources_state.dart';
import 'package:argus/features/sources/presentation/library_folder_picker.dart';
import 'package:argus/features/sources/presentation/root_detail_page.dart';
import 'package:argus/features/sources/presentation/sources_page.dart';
import 'package:argus/features/sources/sources_composition.dart';
import 'package:argus/features/jobs/jobs_composition.dart';
import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sources_test_fakes.dart';
import '../jobs/jobs_test_fakes.dart';

const _rootId = LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
const _runtimeId = RuntimeInstanceId('1234567890abcdef1234567890abcdef');

List<LibraryRoot> manyRoots(int count) => [
  for (var index = 0; index < count; index++)
    fakeRoot(
      id: (index + 1).toRadixString(16).padLeft(32, '0'),
      displayName: 'Root $index',
    ),
];

ProviderContainer createContainer(
  FakeSourcesApi api, {
  LibraryFolderPicker? picker,
  Stream<SourcesReconciliationDemand>? demands,
  FakeJobsApi? jobsApi,
}) {
  final container = ProviderContainer(
    overrides: [
      sourcesApiProvider.overrideWithValue(api),
      sourcesRuntimeContextProvider.overrideWith(
        (ref) =>
            const SourcesRuntimeContext.ready(runtimeInstanceId: _runtimeId),
      ),
      sourcesReconciliationDemandProvider.overrideWith(
        (ref) => SourcesReconciliationDemandSource(
          demands ?? const Stream<SourcesReconciliationDemand>.empty(),
        ),
      ),
      if (jobsApi != null) jobsApiProvider.overrideWithValue(jobsApi),
      if (picker != null) libraryFolderPickerProvider.overrideWithValue(picker),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> pumpDetail(
  WidgetTester tester,
  ProviderContainer container, {
  VoidCallback? onMissingRoot,
  VoidCallback? onRemoved,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ArgusTheme.light,
        home: SourcesRootDetailPage(
          rootId: _rootId,
          onMissingRoot: onMissingRoot ?? () {},
          onRemoved: onRemoved ?? () {},
          onOpenRoot: (_) {},
          onOpenJob: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> settle() async {
  for (var i = 0; i < 100; i++) {
    await Future<void>.value();
  }
}

Future<void> waitForList(
  ProviderContainer container,
  bool Function(AsyncValue<SourcesRootListState> value) predicate,
) async {
  final current = container.read(sourcesRootListControllerProvider);
  if (predicate(current)) return;
  final completer = Completer<void>();
  final subscription = container.listen<AsyncValue<SourcesRootListState>>(
    sourcesRootListControllerProvider,
    (previous, next) {
      if (predicate(next) && !completer.isCompleted) completer.complete();
    },
  );
  addTearDown(subscription.close);
  await completer.future.timeout(const Duration(seconds: 5));
}

Future<void> waitForDetail(
  ProviderContainer container,
  LibraryRootId rootId,
  bool Function(AsyncValue<SourcesRootDetailState> value) predicate,
) async {
  final current = container.read(sourcesRootDetailControllerProvider(rootId));
  if (predicate(current)) return;
  final completer = Completer<void>();
  final subscription = container.listen<AsyncValue<SourcesRootDetailState>>(
    sourcesRootDetailControllerProvider(rootId),
    (previous, next) {
      if (predicate(next) && !completer.isCompleted) completer.complete();
    },
  );
  addTearDown(subscription.close);
  await completer.future.timeout(const Duration(seconds: 5));
}

void main() {
  group('root list controller', () {
    test('loads the empty authoritative page', () async {
      final container = createContainer(FakeSourcesApi());
      await waitForList(container, (value) => value.hasValue);

      final state = container.read(sourcesRootListControllerProvider);
      expect(state.value, isA<SourcesRootListStateReady>());
      final ready = state.value! as SourcesRootListStateReady;
      expect(ready.totalCount, 0);
      expect(ready.roots, isEmpty);
    });

    test('loads configured roots', () async {
      final api = FakeSourcesApi(roots: [fakeRoot()]);
      final container = createContainer(api);
      await waitForList(container, (value) => value.hasValue);

      final ready =
          container.read(sourcesRootListControllerProvider).value!
              as SourcesRootListStateReady;
      expect(ready.totalCount, 1);
      expect(ready.roots.single.displayName, 'Games');
    });

    test('initial failure is retryable', () async {
      final api = FakeSourcesApi();
      final container = createContainer(api);
      api.getFailure = transportFailure();
      api.listFailure = transportFailure();
      await waitForList(container, (value) => value.hasError);
      expect(
        container.read(sourcesRootListControllerProvider).hasError,
        isTrue,
      );

      api.listFailure = null;
      await container
          .read(sourcesRootListControllerProvider.notifier)
          .refresh();
      final ready =
          container.read(sourcesRootListControllerProvider).value!
              as SourcesRootListStateReady;
      expect(ready.totalCount, 0);
    });

    test('refresh failure preserves confirmed roots', () async {
      final api = FakeSourcesApi(roots: [fakeRoot()]);
      final container = createContainer(api);
      await waitForList(container, (value) => value.hasValue);

      api.listFailure = transportFailure();
      await container
          .read(sourcesRootListControllerProvider.notifier)
          .refresh();
      final ready =
          container.read(sourcesRootListControllerProvider).value!
              as SourcesRootListStateReady;
      expect(ready.roots.single.displayName, 'Games');
      expect(ready.lastFailure, isA<TransportFailure>());
    });

    test('roots-changed demand triggers a focused refresh', () async {
      final api = FakeSourcesApi(roots: [fakeRoot()]);
      final demands = StreamController<SourcesReconciliationDemand>.broadcast();
      final container = createContainer(api, demands: demands.stream);
      await waitForList(container, (value) => value.hasValue);
      final before = api.listCalls;

      demands.add(const SourcesReconciliationDemand.rootsChanged());
      await Future<void>.delayed(Duration.zero);

      expect(api.listCalls, greaterThan(before));
      await demands.close();
    });

    test('first page keeps authoritative totalCount distinct from loaded '
        'roots', () async {
      final api = FakeSourcesApi(roots: manyRoots(130));
      final container = createContainer(api);
      await waitForList(container, (value) => value.hasValue);

      final ready =
          container.read(sourcesRootListControllerProvider).value!
              as SourcesRootListStateReady;
      expect(ready.roots.length, 100);
      expect(ready.totalCount, 130);
      expect(ready.hasMore, isTrue);
      expect(ready.nextOffset, 100);
    });

    test('loading the next page appends in deterministic order without '
        'duplicates', () async {
      final api = FakeSourcesApi(roots: manyRoots(130));
      final container = createContainer(api);
      await waitForList(container, (value) => value.hasValue);

      await container
          .read(sourcesRootListControllerProvider.notifier)
          .loadMore();
      await settle();

      final ready =
          container.read(sourcesRootListControllerProvider).value!
              as SourcesRootListStateReady;
      expect(ready.roots.length, 130);
      expect(ready.totalCount, 130);
      expect(ready.hasMore, isFalse);
      expect(ready.roots.map((root) => root.id).toSet().length, 130);
    });

    test(
      'next-page failure preserves confirmed roots and remains retryable',
      () async {
        final api = FakeSourcesApi(roots: manyRoots(130));
        final container = createContainer(api);
        await waitForList(container, (value) => value.hasValue);

        api.listFailure = transportFailure();
        await container
            .read(sourcesRootListControllerProvider.notifier)
            .loadMore();
        await settle();
        var ready =
            container.read(sourcesRootListControllerProvider).value!
                as SourcesRootListStateReady;
        expect(ready.roots.length, 100);
        expect(ready.loadMoreFailed, isTrue);
        expect(ready.lastFailure, isA<TransportFailure>());

        api.listFailure = null;
        await container
            .read(sourcesRootListControllerProvider.notifier)
            .loadMore();
        await settle();
        ready =
            container.read(sourcesRootListControllerProvider).value!
                as SourcesRootListStateReady;
        expect(ready.roots.length, 130);
        expect(ready.loadMoreFailed, isFalse);
        expect(ready.lastFailure, isNull);
      },
    );

    test('refresh rebuilds the authoritative paged list safely', () async {
      final api = FakeSourcesApi(roots: manyRoots(130));
      final container = createContainer(api);
      await waitForList(container, (value) => value.hasValue);
      await container
          .read(sourcesRootListControllerProvider.notifier)
          .loadMore();
      await settle();

      api.roots = manyRoots(3);
      await container
          .read(sourcesRootListControllerProvider.notifier)
          .refresh();
      await settle();

      final ready =
          container.read(sourcesRootListControllerProvider).value!
              as SourcesRootListStateReady;
      expect(ready.roots.length, 3);
      expect(ready.totalCount, 3);
      expect(ready.nextOffset, 3);
      expect(ready.hasMore, isFalse);
    });
  });

  group('root detail controller', () {
    test('loads one authoritative root', () async {
      final api = FakeSourcesApi(roots: [fakeRoot()]);
      final container = createContainer(api);
      await waitForDetail(container, _rootId, (value) => value.hasValue);

      final state = container.read(
        sourcesRootDetailControllerProvider(_rootId),
      );
      final ready = state.value! as SourcesRootDetailStateReady;
      expect(ready.root.displayName, 'Games');
      expect(ready.root.lastScan, isNull);
    });

    test('valid-but-missing root becomes the typed missing state', () async {
      final container = createContainer(FakeSourcesApi());
      await waitForDetail(container, _rootId, (value) => value.hasValue);
      await settle();

      final state = container.read(
        sourcesRootDetailControllerProvider(_rootId),
      );
      expect(state.value, isA<SourcesRootDetailStateMissing>());
    });

    test('root-changed demand refreshes only the matching root', () async {
      final api = FakeSourcesApi(roots: [fakeRoot()]);
      final demands = StreamController<SourcesReconciliationDemand>.broadcast();
      final container = createContainer(api, demands: demands.stream);
      await waitForDetail(container, _rootId, (value) => value.hasValue);
      final before = api.getCalls;

      demands.add(
        const SourcesReconciliationDemand.rootChanged(
          libraryRootId: LibraryRootId('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(api.getCalls, before);

      demands.add(
        const SourcesReconciliationDemand.rootChanged(libraryRootId: _rootId),
      );
      await Future<void>.delayed(Duration.zero);
      expect(api.getCalls, greaterThan(before));
      await demands.close();
    });

    test('confirmed root stays visible during failed refresh', () async {
      final api = FakeSourcesApi(roots: [fakeRoot()]);
      final container = createContainer(api);
      await waitForDetail(container, _rootId, (value) => value.hasValue);

      api.getFailure = transportFailure();
      await container
          .read(sourcesRootDetailControllerProvider(_rootId).notifier)
          .refresh(_rootId);
      final state = container.read(
        sourcesRootDetailControllerProvider(_rootId),
      );
      final ready = state.value! as SourcesRootDetailStateReady;
      expect(ready.root.displayName, 'Games');
      expect(ready.lastFailure, isA<TransportFailure>());
    });

    test('ambiguous removal clears after authoritative existence '
        'reconciliation', () async {
      final api = FakeSourcesApi(roots: [fakeRoot()]);
      final container = createContainer(api);
      await waitForDetail(container, _rootId, (value) => value.hasValue);
      api.onRemove = (id) => throw transportFailure();

      await container
          .read(sourcesRootDetailControllerProvider(_rootId).notifier)
          .remove(_rootId);

      expect(api.removeCalls, 1);
      expect(api.getCalls, greaterThan(0));
      final ready =
          container.read(sourcesRootDetailControllerProvider(_rootId)).value!
              as SourcesRootDetailStateReady;
      expect(ready.removalAmbiguous, isFalse);
      expect(ready.lastFailure, isNull);
      expect(ready.root.displayName, 'Games');
    });

    test('ambiguous removal resolves as missing when reconciliation reports '
        'not found', () async {
      final api = FakeSourcesApi(roots: [fakeRoot()]);
      final container = createContainer(api);
      await waitForDetail(container, _rootId, (value) => value.hasValue);
      api.onRemove = (id) => throw transportFailure();
      api.getFailure = rootNotFoundFailure();

      await container
          .read(sourcesRootDetailControllerProvider(_rootId).notifier)
          .remove(_rootId);

      expect(api.removeCalls, 1);
      expect(
        container.read(sourcesRootDetailControllerProvider(_rootId)).value,
        isA<SourcesRootDetailStateMissing>(),
      );
    });

    test(
      'reconciliation failure preserves ambiguity and confirmed root',
      () async {
        final api = FakeSourcesApi(roots: [fakeRoot()]);
        final container = createContainer(api);
        await waitForDetail(container, _rootId, (value) => value.hasValue);
        api.onRemove = (id) => throw transportFailure();
        api.getFailure = transportFailure();

        await container
            .read(sourcesRootDetailControllerProvider(_rootId).notifier)
            .remove(_rootId);

        final ready =
            container.read(sourcesRootDetailControllerProvider(_rootId)).value!
                as SourcesRootDetailStateReady;
        expect(ready.removalAmbiguous, isTrue);
        expect(ready.lastFailure, isA<TransportFailure>());
        expect(ready.root.displayName, 'Games');
      },
    );

    test('remove() is a no-op while removal ambiguity is unresolved', () async {
      final api = FakeSourcesApi(roots: [fakeRoot()]);
      final container = createContainer(api);
      await waitForDetail(container, _rootId, (value) => value.hasValue);
      api.onRemove = (id) => throw transportFailure();
      api.getFailure = transportFailure();
      await container
          .read(sourcesRootDetailControllerProvider(_rootId).notifier)
          .remove(_rootId);
      final ready =
          container.read(sourcesRootDetailControllerProvider(_rootId)).value!
              as SourcesRootDetailStateReady;
      expect(ready.removalAmbiguous, isTrue);
      final callsAfterFirst = api.removeCalls;

      // A direct controller repeat must be rejected at the boundary: no
      // second RemoveLibraryRoot call while the outcome is unresolved.
      await container
          .read(sourcesRootDetailControllerProvider(_rootId).notifier)
          .remove(_rootId);
      expect(api.removeCalls, callsAfterFirst);
    });
  });

  group('add workflow controller', () {
    test('added outcome adopts the committed root', () async {
      final container = createContainer(FakeSourcesApi());
      final notifier = container.read(
        sourcesAddLibraryFolderControllerProvider.notifier,
      );

      await notifier.add(const LocalFilesystemRootSelection('/tmp/games'));

      expect(
        container.read(sourcesAddLibraryFolderControllerProvider),
        isA<SourcesAddOperationAdded>(),
      );
    });

    test('already-configured and overlap outcomes stay non-mutating', () async {
      final api = FakeSourcesApi();
      final container = createContainer(api);
      final notifier = container.read(
        sourcesAddLibraryFolderControllerProvider.notifier,
      );
      api.onAdd = (selection) =>
          AddLocalLibraryRootResult.alreadyConfigured(_rootId);
      await notifier.add(const LocalFilesystemRootSelection('/tmp/games'));
      expect(
        container.read(sourcesAddLibraryFolderControllerProvider),
        SourcesAddOperation.alreadyConfigured(_rootId),
      );
      expect(api.addCalls, 1);

      api.onAdd = (selection) => AddLocalLibraryRootResult.overlapsExisting(
        existingLibraryRootId: _rootId,
        relationship: RootRelationship.ancestor,
      );
      notifier.reset();
      await notifier.add(const LocalFilesystemRootSelection('/tmp/games'));
      expect(
        container.read(sourcesAddLibraryFolderControllerProvider),
        const SourcesAddOperation.overlapsExisting(
          existingLibraryRootId: _rootId,
          relationship: RootRelationship.ancestor,
        ),
      );
      expect(api.addCalls, 2);
    });

    test(
      'ambiguous transport replays only the idempotent root-only add',
      () async {
        final api = FakeSourcesApi();
        final container = createContainer(api);
        final notifier = container.read(
          sourcesAddLibraryFolderControllerProvider.notifier,
        );
        var first = true;
        api.onAdd = (selection) {
          if (first) {
            first = false;
            throw transportFailure();
          }
          return AddLocalLibraryRootResult.added(fakeRoot());
        };

        await notifier.add(const LocalFilesystemRootSelection('/tmp/games'));

        expect(api.addCalls, 2);
        expect(
          container.read(sourcesAddLibraryFolderControllerProvider),
          isA<SourcesAddOperationAdded>(),
        );
      },
    );

    test('definite application failure is not replayed', () async {
      final api = FakeSourcesApi();
      final container = createContainer(api);
      final notifier = container.read(
        sourcesAddLibraryFolderControllerProvider.notifier,
      );
      api.onAdd = (selection) => throw rootNotFoundFailure();

      await notifier.add(const LocalFilesystemRootSelection('/tmp/games'));

      expect(api.addCalls, 1);
      expect(
        container.read(sourcesAddLibraryFolderControllerProvider),
        isA<SourcesAddOperationFailed>(),
      );
    });
  });

  group('removal workflow', () {
    test('confirmed removal transitions to missing', () async {
      final api = FakeSourcesApi(roots: [fakeRoot()]);
      final container = createContainer(api);
      await waitForDetail(container, _rootId, (value) => value.hasValue);

      await container
          .read(sourcesRootDetailControllerProvider(_rootId).notifier)
          .remove(_rootId);

      expect(api.removeCalls, 1);
      expect(
        container.read(sourcesRootDetailControllerProvider(_rootId)).value,
        isA<SourcesRootDetailStateMissing>(),
      );
    });

    test(
      'ambiguous removal reconciles authoritatively and never repeats',
      () async {
        final api = FakeSourcesApi(roots: [fakeRoot()]);
        final container = createContainer(api);
        await waitForDetail(container, _rootId, (value) => value.hasValue);
        final getCallsBefore = api.getCalls;
        api.onRemove = (id) => throw transportFailure();

        await container
            .read(sourcesRootDetailControllerProvider(_rootId).notifier)
            .remove(_rootId);

        expect(api.removeCalls, 1);
        expect(api.getCalls, greaterThan(getCallsBefore));
        final state = container.read(
          sourcesRootDetailControllerProvider(_rootId),
        );
        final ready = state.value! as SourcesRootDetailStateReady;
        expect(ready.removalAmbiguous, isFalse);
        expect(ready.lastFailure, isNull);
        expect(ready.root.displayName, 'Games');
      },
    );
  });

  group('sidebar session preference', () {
    test('adaptive defaults and explicit override follow FE-008', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        sourcesSidebarPreferenceProvider.notifier,
      );
      expect(
        container.read(sourcesSidebarPreferenceProvider),
        SourcesSidebarOverride.none,
      );

      notifier.collapse();
      expect(
        container.read(sourcesSidebarPreferenceProvider),
        SourcesSidebarOverride.collapsed,
      );
      notifier.expand();
      expect(
        container.read(sourcesSidebarPreferenceProvider),
        SourcesSidebarOverride.expanded,
      );
    });

    test('a fresh provider scope resets the override', () async {
      final first = ProviderContainer();
      first.read(sourcesSidebarPreferenceProvider.notifier).collapse();
      expect(
        first.read(sourcesSidebarPreferenceProvider),
        SourcesSidebarOverride.collapsed,
      );
      first.dispose();

      final second = ProviderContainer();
      addTearDown(second.dispose);
      expect(
        second.read(sourcesSidebarPreferenceProvider),
        SourcesSidebarOverride.none,
      );
    });
  });

  group('Sources presentation', () {
    Future<void> pumpPage(
      WidgetTester tester,
      ProviderContainer container, {
      void Function(LibraryRootId rootId)? onOpenRoot,
      void Function(JobRunId jobRunId)? onOpenJob,
      ThemeData? theme,
    }) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: theme ?? ArgusTheme.light,
            home: SourcesPage(
              onOpenRoot: onOpenRoot ?? (_) {},
              onOpenJob: onOpenJob ?? (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'empty state explains Library Folders and never modifies files',
      (tester) async {
        final container = createContainer(FakeSourcesApi());
        await pumpPage(tester, container);

        expect(find.text('No library folders yet'), findsOneWidget);
        expect(
          find.textContaining('does not modify your files'),
          findsOneWidget,
        );
        expect(find.text('Scan All'), findsNothing);
        expect(find.text('Add Library Folder'), findsOneWidget);
      },
    );

    testWidgets('picker cancellation and confirmation cancellation mutate '
        'nothing', (tester) async {
      final api = FakeSourcesApi();
      final container = createContainer(api, picker: () async => null);
      await pumpPage(tester, container);

      await tester.tap(find.text('Add Library Folder'));
      await tester.pumpAndSettle();
      expect(api.addCalls, 0);

      final selection = const LocalFilesystemRootSelection('/tmp/games');
      final container2 = createContainer(api, picker: () async => selection);
      await pumpPage(tester, container2);
      await tester.tap(find.text('Add Library Folder'));
      await tester.pumpAndSettle();
      expect(find.text('Add Library Folder?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('add-folder-cancel')));
      await tester.pumpAndSettle();
      expect(api.addCalls, 0);
    });

    testWidgets('confirmation offers Add & Scan primary and Add Without '
        'Scanning secondary', (tester) async {
      final api = FakeSourcesApi();
      final container = createContainer(
        api,
        picker: () async => const LocalFilesystemRootSelection('/tmp/games'),
      );
      await pumpPage(tester, container);

      await tester.tap(find.text('Add Library Folder'));
      await tester.pumpAndSettle();
      expect(find.text('Add Library Folder?'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('add-folder-and-scan')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('add-folder-without-scan')),
        findsOneWidget,
      );
      expect(find.text('Add & Scan'), findsOneWidget);
      expect(find.text('Add Without Scanning'), findsOneWidget);
    });

    testWidgets('Add Without Scanning adds the root without admitting a scan', (
      tester,
    ) async {
      final api = FakeSourcesApi();
      final opened = <LibraryRootId>[];
      final container = createContainer(
        api,
        picker: () async => const LocalFilesystemRootSelection('/tmp/games'),
      );
      await pumpPage(tester, container, onOpenRoot: opened.add);

      await tester.tap(find.text('Add Library Folder'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('add-folder-without-scan')),
      );
      await tester.pumpAndSettle();

      expect(opened, isNotEmpty);
      expect(api.addCalls, 1);
      expect(api.addAndScanCalls, 0);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('Add & Scan uses the composite workflow and opens the root', (
      tester,
    ) async {
      final api = FakeSourcesApi();
      final opened = <LibraryRootId>[];
      final container = createContainer(
        api,
        picker: () async => const LocalFilesystemRootSelection('/tmp/games'),
      );
      await pumpPage(tester, container, onOpenRoot: opened.add);

      await tester.tap(find.text('Add Library Folder'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('add-folder-and-scan')),
      );
      await tester.pumpAndSettle();

      expect(opened, isNotEmpty);
      expect(api.addCalls, 0);
      expect(api.addAndScanCalls, 1);
    });

    testWidgets('AddedButScanNotAdmitted preserves the root and shows a '
        'bounded notice', (tester) async {
      final api = FakeSourcesApi()
        ..onAddAndScan = (selection) =>
            AddLocalLibraryRootAndScanResult.addedButScanNotAdmitted(
              root: fakeRoot(),
              issue: LibraryScanChildAdmissionIssue.admissionFailure(
                ClientApplicationError(
                  code: const ErrorCode(
                    'ARGUS.V1.OPERATION.CAPACITY_UNAVAILABLE',
                  ),
                  category: ErrorCategory.operation,
                  severity: ApplicationSeverity.error,
                  recoverability: Recoverability.userAction,
                  retryPolicy: RetryPolicy.userInitiated,
                  messageKey: const MessageKey('errors.operation.capacity'),
                  traceId: const TraceId('11111111111111111111111111111111'),
                  safeContext: const [],
                ),
              ),
            );
      final opened = <LibraryRootId>[];
      final container = createContainer(
        api,
        picker: () async => const LocalFilesystemRootSelection('/tmp/games'),
      );
      await pumpPage(tester, container, onOpenRoot: opened.add);

      await tester.tap(find.text('Add Library Folder'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('add-folder-and-scan')),
      );
      await tester.pumpAndSettle();

      expect(opened, isNotEmpty);
      expect(find.textContaining('scan could not start'), findsOneWidget);
    });

    testWidgets('ambiguous Add & Scan never replays the composite and keeps '
        'conflicting mutation disabled until authority proves no admission', (
      tester,
    ) async {
      final api = FakeSourcesApi(roots: [fakeRoot()])
        ..onAddAndScan = (selection) {
          throw transportFailure();
        }
        ..onAdd = (selection) {
          return AddLocalLibraryRootResult.added(fakeRoot());
        }
        ..onStartScan = (rootId) {
          throw transportFailure();
        };
      final jobsApi = FakeJobsApi()..onRootScanAdmission = (_) => null;
      final container = createContainer(
        api,
        picker: () async => const LocalFilesystemRootSelection('/tmp/games'),
        jobsApi: jobsApi,
      );
      await pumpPage(tester, container);

      await tester.tap(find.text('Add Library Folder'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('add-folder-and-scan')),
      );
      await tester.pumpAndSettle();

      expect(api.addAndScanCalls, 1, reason: 'the composite is never replayed');
      expect(api.addCalls, 1, reason: 'only the idempotent add is replayed');
      expect(jobsApi.rootScanAdmissionCalls, 1);
      expect(api.startScanCalls, 1);
      expect(find.text('Scan not confirmed'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
    });

    testWidgets('picker failure is sanitized and performs no mutation', (
      tester,
    ) async {
      final api = FakeSourcesApi();
      final container = createContainer(
        api,
        picker: () async => throw StateError('native picker exploded'),
      );
      await pumpPage(tester, container);

      await tester.tap(find.text('Add Library Folder'));
      await tester.pumpAndSettle();

      expect(api.addCalls, 0);
      expect(find.textContaining('could not be opened'), findsOneWidget);
      expect(find.textContaining('exploded'), findsNothing);
    });

    testWidgets('configured roots list opens the routed detail', (
      tester,
    ) async {
      final opened = <LibraryRootId>[];
      final container = createContainer(FakeSourcesApi(roots: [fakeRoot()]));
      await pumpPage(tester, container, onOpenRoot: opened.add);

      expect(find.text('Games'), findsOneWidget);
      expect(find.text('Never scanned'), findsOneWidget);
      await tester.tap(find.text('Games'));
      await tester.pumpAndSettle();
      expect(opened.single, _rootId);
    });

    testWidgets('detail shows independent never-scanned state and safe '
        'removal copy', (tester) async {
      final container = createContainer(FakeSourcesApi(roots: [fakeRoot()]));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ArgusTheme.light,
            home: SourcesRootDetailPage(
              rootId: _rootId,
              onMissingRoot: () {},
              onRemoved: () {},
              onOpenRoot: (_) {},
              onOpenJob: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Games'), findsOneWidget);
      expect(find.text('Never scanned'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('sources-remove-library-folder')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remove Library Folder?'), findsOneWidget);
      expect(
        find.textContaining('Files on disk are not changed'),
        findsOneWidget,
      );
    });

    testWidgets('terminal history shows Scan Again and admits a fresh scan', (
      tester,
    ) async {
      final api = FakeSourcesApi(
        roots: [
          fakeRoot().copyWith(
            lastScan: LibraryRootLastScan(
              scanRunId: 'scan',
              jobRunId: 'job',
              status: LibraryRootLastScanStatus.failed,
              startedAtMs: 1,
              completedAtMs: 2,
            ),
          ),
        ],
      );
      final container = createContainer(api);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ArgusTheme.light,
            home: SourcesRootDetailPage(
              rootId: _rootId,
              onMissingRoot: () {},
              onRemoved: () {},
              onOpenRoot: (_) {},
              onOpenJob: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Scan Again'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('sources-start-scan')),
      );
      await tester.pumpAndSettle();
      expect(api.startScanCalls, 1);
    });

    testWidgets('removal confirmation cancel keeps the root', (tester) async {
      final api = FakeSourcesApi(roots: [fakeRoot()]);
      final container = createContainer(api);
      var removed = false;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ArgusTheme.light,
            home: SourcesRootDetailPage(
              rootId: _rootId,
              onMissingRoot: () {},
              onRemoved: () => removed = true,
              onOpenRoot: (_) {},
              onOpenJob: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('sources-remove-library-folder')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('remove-root-cancel')),
      );
      await tester.pumpAndSettle();

      expect(api.removeCalls, 0);
      expect(removed, isFalse);
    });

    testWidgets('confirmed removal canonicalizes through the callback', (
      tester,
    ) async {
      final api = FakeSourcesApi(roots: [fakeRoot()]);
      final container = createContainer(api);
      var removed = false;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ArgusTheme.light,
            home: SourcesRootDetailPage(
              rootId: _rootId,
              onMissingRoot: () {},
              onRemoved: () => removed = true,
              onOpenRoot: (_) {},
              onOpenJob: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('sources-remove-library-folder')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('remove-root-confirm')),
      );
      await tester.pumpAndSettle();

      expect(api.removeCalls, 1);
      expect(removed, isTrue);
    });

    testWidgets('ambiguous remove disables Remove while reconciliation is '
        'unresolved', (tester) async {
      final api = FakeSourcesApi(roots: [fakeRoot()]);
      api.onRemove = (id) => throw transportFailure();
      final container = createContainer(api);
      await pumpDetail(tester, container);

      await tester.tap(
        find.byKey(const ValueKey<String>('sources-remove-library-folder')),
      );
      await tester.pumpAndSettle();
      // The reconciliation read must fail only after the initial load.
      api.getFailure = transportFailure();
      await tester.tap(
        find.byKey(const ValueKey<String>('remove-root-confirm')),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey<String>('sources-remove-library-folder')),
      );
      expect(button.onPressed, isNull);
      expect(
        find.textContaining('could not confirm whether the folder was removed'),
        findsOneWidget,
      );
    });

    testWidgets('successful reconciliation clears ambiguity and re-enables '
        'Remove', (tester) async {
      final api = FakeSourcesApi(roots: [fakeRoot()]);
      api.onRemove = (id) => throw transportFailure();
      final container = createContainer(api);
      await pumpDetail(tester, container);

      await tester.tap(
        find.byKey(const ValueKey<String>('sources-remove-library-folder')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('remove-root-confirm')),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey<String>('sources-remove-library-folder')),
      );
      expect(button.onPressed, isNotNull);
      expect(
        find.textContaining('could not confirm whether the folder was removed'),
        findsNothing,
      );
    });

    testWidgets('ambiguous removal that reconciled as missing canonicalizes', (
      tester,
    ) async {
      var canonicalized = false;
      final api = FakeSourcesApi(roots: [fakeRoot()]);
      api.onRemove = (id) => throw transportFailure();
      final container = createContainer(api);
      await pumpDetail(
        tester,
        container,
        onMissingRoot: () {
          canonicalized = true;
        },
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('sources-remove-library-folder')),
      );
      await tester.pumpAndSettle();
      api.getFailure = rootNotFoundFailure();
      await tester.tap(
        find.byKey(const ValueKey<String>('remove-root-confirm')),
      );
      await tester.pumpAndSettle();

      expect(canonicalized, isTrue);
    });

    testWidgets('Load More affordance appears only while more roots exist', (
      tester,
    ) async {
      final api = FakeSourcesApi(roots: manyRoots(130));
      final container = createContainer(api);
      await pumpPage(tester, container);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('sources-load-more')),
        300,
        scrollable: find.byType(Scrollable),
      );
      expect(
        find.byKey(const ValueKey<String>('sources-load-more')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey<String>('sources-load-more')));
      await tester.pumpAndSettle();

      final ready =
          container.read(sourcesRootListControllerProvider).value!
              as SourcesRootListStateReady;
      expect(ready.roots.length, 130);
      expect(ready.hasMore, isFalse);
      await tester.scrollUntilVisible(
        find.text('Root 129'),
        300,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Load more folders'), findsNothing);
    });

    testWidgets('missing root triggers canonicalization', (tester) async {
      var canonicalized = false;
      final container = createContainer(FakeSourcesApi());
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ArgusTheme.light,
            home: SourcesRootDetailPage(
              rootId: _rootId,
              onMissingRoot: () => canonicalized = true,
              onRemoved: () {},
              onOpenRoot: (_) {},
              onOpenJob: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      expect(canonicalized, isTrue);
    });

    testWidgets('Expanded/Large detail uses the collapsible root sidebar', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.reset);
      final container = createContainer(
        FakeSourcesApi(
          roots: [
            fakeRoot(),
            fakeRoot(
              id: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              displayName: 'Retro',
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ArgusTheme.light,
            home: SourcesRootDetailPage(
              rootId: _rootId,
              onMissingRoot: () {},
              onRemoved: () {},
              onOpenRoot: (_) {},
              onOpenJob: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Two roots default to an expanded sidebar.
      expect(
        find.byKey(const ValueKey<String>('sources-sidebar-list')),
        findsOneWidget,
      );
      expect(find.text('Library folders'), findsOneWidget);
      expect(find.text('Retro'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('sources-sidebar-collapse')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('sources-sidebar-expand')),
        findsOneWidget,
      );
      expect(find.text('Retro'), findsNothing);
    });

    testWidgets('expanding the root sidebar never lays out tiles at '
        'animation widths', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.reset);
      final api = FakeSourcesApi(roots: [fakeRoot()]);
      final container = createContainer(api);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ArgusTheme.light,
            home: SourcesRootDetailPage(
              rootId: _rootId,
              onMissingRoot: () {},
              onRemoved: () {},
              onOpenRoot: (_) {},
              onOpenJob: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // One root defaults to the collapsed sidebar at expanded width.
      expect(
        find.byKey(const ValueKey<String>('sources-sidebar-expand')),
        findsOneWidget,
      );

      // A second root becomes configured; the sidebar expands directly to
      // its full width without laying out ListTiles at too-narrow
      // intermediate sizes.
      api.roots = [
        fakeRoot(),
        fakeRoot(id: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', displayName: 'Retro'),
      ];
      await container
          .read(sourcesRootListControllerProvider.notifier)
          .refresh();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('sources-sidebar-list')),
        findsOneWidget,
      );
      expect(find.text('Retro'), findsOneWidget);
    });

    group('root sidebar pagination', () {
      Future<void> pumpWideDetail(
        WidgetTester tester,
        ProviderContainer container, {
        LibraryRootId rootId = _rootId,
      }) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 800);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ArgusTheme.light,
              home: SourcesRootDetailPage(
                rootId: rootId,
                onMissingRoot: () {},
                onRemoved: () {},
                onOpenRoot: (_) {},
                onOpenJob: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Finder sidebarScrollable() => find.descendant(
        of: find.byKey(const ValueKey<String>('sources-sidebar-list')),
        matching: find.byType(Scrollable),
      );

      Finder sidebarText(String text) => find.descendant(
        of: find.byKey(const ValueKey<String>('sources-sidebar-list')),
        matching: find.text(text),
      );

      testWidgets('expanded sidebar exposes Load More when more roots exist', (
        tester,
      ) async {
        final container = createContainer(
          FakeSourcesApi(roots: manyRoots(130)),
        );
        await pumpWideDetail(tester, container);

        expect(
          find.byKey(const ValueKey<String>('sources-sidebar-load-more')),
          findsOneWidget,
        );
        expect(find.text('Load more folders'), findsOneWidget);
      });

      testWidgets('loading the next page makes later roots available in the '
          'sidebar without duplicates', (tester) async {
        final container = createContainer(
          FakeSourcesApi(roots: manyRoots(130)),
        );
        await pumpWideDetail(tester, container);

        await tester.tap(
          find.byKey(const ValueKey<String>('sources-sidebar-load-more')),
        );
        await tester.pumpAndSettle();

        final ready =
            container.read(sourcesRootListControllerProvider).value!
                as SourcesRootListStateReady;
        expect(ready.roots.length, 130);
        expect(ready.hasMore, isFalse);
        await tester.scrollUntilVisible(
          sidebarText('Root 129'),
          300,
          scrollable: sidebarScrollable(),
        );
        expect(sidebarText('Root 129'), findsOneWidget);
        expect(ready.roots.map((root) => root.id).toSet().length, 130);
        expect(
          find.byKey(const ValueKey<String>('sources-sidebar-load-more')),
          findsNothing,
        );
      });

      testWidgets('sidebar next-page failure preserves loaded roots and '
          'exposes retry', (tester) async {
        final api = FakeSourcesApi(roots: manyRoots(130));
        final container = createContainer(api);
        await pumpWideDetail(tester, container);

        api.listFailure = transportFailure();
        await tester.tap(
          find.byKey(const ValueKey<String>('sources-sidebar-load-more')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('sources-sidebar-load-more-retry')),
          findsOneWidget,
        );
        final ready =
            container.read(sourcesRootListControllerProvider).value!
                as SourcesRootListStateReady;
        expect(ready.roots.length, 100);
        expect(sidebarText('Root 0'), findsOneWidget);

        api.listFailure = null;
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey<String>('sources-sidebar-load-more-retry')),
          300,
          scrollable: sidebarScrollable(),
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('sources-sidebar-load-more-retry')),
        );
        await tester.pumpAndSettle();
        expect(
          (container.read(sourcesRootListControllerProvider).value!
                  as SourcesRootListStateReady)
              .roots
              .length,
          130,
        );
        expect(
          find.byKey(const ValueKey<String>('sources-sidebar-load-more-retry')),
          findsNothing,
        );
      });

      testWidgets('a routed root beyond the first page becomes represented '
          'after bounded loading', (tester) async {
        const deepId = 'ffffffffffffffffffffffffffffffff';
        final api = FakeSourcesApi(
          roots: [
            ...manyRoots(129),
            fakeRoot(id: deepId, displayName: 'Deep'),
          ],
        );
        final container = createContainer(api);
        await pumpWideDetail(
          tester,
          container,
          rootId: const LibraryRootId(deepId),
        );

        expect(sidebarText('Deep'), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey<String>('sources-sidebar-load-more')),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          sidebarText('Deep'),
          300,
          scrollable: sidebarScrollable(),
        );
        expect(sidebarText('Deep'), findsOneWidget);
      });
    });

    testWidgets('Dark theme remains legible and free of exceptions', (
      tester,
    ) async {
      final container = createContainer(FakeSourcesApi(roots: [fakeRoot()]));
      await pumpPage(tester, container, theme: ArgusTheme.dark);

      expect(find.text('Games'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('representative 2.0x text scale remains usable', (
      tester,
    ) async {
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      final container = createContainer(FakeSourcesApi(roots: [fakeRoot()]));
      await pumpPage(tester, container);

      expect(find.text('Games'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
