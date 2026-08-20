import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:argus/core/design_system/argus_theme.dart';
import 'package:argus/features/sources/application/sources_state.dart';
import 'package:argus/features/sources/presentation/hierarchy_drill_down_view.dart';
import 'package:argus/features/sources/presentation/hierarchy_tree_view.dart';
import 'package:argus/features/sources/presentation/source_hierarchy_browser.dart';
import 'package:argus/features/sources/sources_composition.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sources_test_fakes.dart';

const _rootId = LibraryRootId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
const _runtimeId = RuntimeInstanceId('1234567890abcdef1234567890abcdef');
const _idA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _idB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _idC = 'cccccccccccccccccccccccccccccccc';
const _idD = 'dddddddddddddddddddddddddddddddd';

SourceEntry dirEntry(String id, String name) => fakeEntry(
  id: id,
  name: name,
  kind: SourceEntryKind.directory,
  classification: SourceEntryClassification.container,
);

SourceEntry fileEntry(String id, String name) => fakeEntry(
  id: id,
  name: name,
  kind: SourceEntryKind.file,
  classification: SourceEntryClassification.unknown,
);

Future<ProviderContainer> pumpBrowser(
  WidgetTester tester,
  FakeSourcesApi api, {
  double width = 1200,
  double height = 800,
  double textScale = 1.0,
  double? contentWidth,
  Stream<SourcesReconciliationDemand>? demands,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ArgusTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: contentWidth,
            child: SourceHierarchyBrowser(rootId: _rootId),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('compact drill-down advances and returns via back', (
    tester,
  ) async {
    final dirA = dirEntry(_idA, 'A');
    final api = FakeSourcesApi()
      ..childrenByParent[''] = [dirA, fileEntry(_idB, 'B')]
      ..childrenByParent[dirA.sourceEntryId.value] = [fileEntry(_idC, 'C')];
    await pumpBrowser(tester, api, width: 400);

    expect(find.text('Library root'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('hierarchy-row-$_idA')));
    await tester.pumpAndSettle();

    expect(find.text('C'), findsOneWidget);
    expect(find.text('B'), findsNothing);
    expect(
      find.text('A'),
      findsOneWidget,
      reason: 'breadcrumb shows current folder',
    );

    await tester.tap(find.byKey(const ValueKey('hierarchy-back')));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets(
    'system Back retreats Compact hierarchy before routed navigation',
    (tester) async {
      final dirA = dirEntry(_idA, 'A');
      final api = FakeSourcesApi()
        ..childrenByParent[''] = [dirA, fileEntry(_idB, 'B')]
        ..childrenByParent[dirA.sourceEntryId.value] = [fileEntry(_idC, 'C')];
      await pumpBrowser(tester, api, width: 400);

      PopScope<void> popScope() =>
          tester.widget<PopScope<void>>(find.byType(PopScope<void>));

      expect(popScope().canPop, isTrue);
      await tester.tap(find.byKey(const ValueKey('hierarchy-row-$_idA')));
      await tester.pumpAndSettle();
      expect(popScope().canPop, isFalse);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('C'), findsNothing);
      expect(find.text('B'), findsOneWidget);
      expect(popScope().canPop, isTrue);
    },
  );

  testWidgets(
    'local pane width chooses hierarchy presentation independently of window',
    (tester) async {
      final api = FakeSourcesApi()
        ..childrenByParent[''] = [fileEntry(_idA, 'A')];
      await pumpBrowser(tester, api, width: 1200, contentWidth: 500);

      expect(find.byType(HierarchyDrillDownView), findsOneWidget);
      expect(find.byType(HierarchyTreeView), findsNothing);
    },
  );

  testWidgets('live pane width changes preserve hierarchy context', (
    tester,
  ) async {
    final dirA = dirEntry(_idA, 'A');
    final api = FakeSourcesApi()
      ..childrenByParent[''] = [dirA, fileEntry(_idB, 'B')]
      ..childrenByParent[dirA.sourceEntryId.value] = [fileEntry(_idC, 'C')];
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        sourcesApiProvider.overrideWithValue(api),
        sourcesRuntimeContextProvider.overrideWith(
          (ref) =>
              const SourcesRuntimeContext.ready(runtimeInstanceId: _runtimeId),
        ),
        sourcesReconciliationDemandProvider.overrideWith(
          (ref) => const SourcesReconciliationDemandSource(
            Stream<SourcesReconciliationDemand>.empty(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final paneWidth = ValueNotifier<double>(500);
    addTearDown(paneWidth.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ArgusTheme.light,
          home: Scaffold(
            body: ValueListenableBuilder<double>(
              valueListenable: paneWidth,
              builder: (context, width, child) => SizedBox(
                width: width,
                child: const SourceHierarchyBrowser(rootId: _rootId),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('hierarchy-row-$_idA')));
    await tester.pumpAndSettle();
    expect(find.text('C'), findsOneWidget);

    paneWidth.value = 1000;
    await tester.pumpAndSettle();
    expect(find.byType(HierarchyTreeView), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(
      tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
      isTrue,
    );

    paneWidth.value = 500;
    await tester.pumpAndSettle();
    expect(find.byType(HierarchyDrillDownView), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(
      tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
      isFalse,
    );
  });

  testWidgets('expanded tree expands and collapses without eager loads', (
    tester,
  ) async {
    final dirA = dirEntry(_idA, 'A');
    final api = FakeSourcesApi()
      ..childrenByParent[''] = [dirA, dirEntry(_idB, 'B')]
      ..childrenByParent[dirA.sourceEntryId.value] = [fileEntry(_idC, 'C')]
      ..detailsByEntry[dirA.sourceEntryId.value] = fakeDetail(
        id: dirA.sourceEntryId.value,
        name: 'A',
      )
      ..childrenByParent[_idB] = [fileEntry(_idD, 'D')];
    await pumpBrowser(tester, api, width: 1200);

    expect(find.text('C'), findsNothing);
    expect(find.text('D'), findsNothing);
    expect(api.listChildrenCalls, 1);

    await tester.tap(find.byKey(const ValueKey('hierarchy-row-$_idA')));
    await tester.pumpAndSettle();
    expect(find.text('C'), findsOneWidget);
    expect(api.listChildrenCalls, 2, reason: 'only the expanded branch loads');

    await tester.tap(find.byKey(const ValueKey('hierarchy-row-$_idA')));
    await tester.pumpAndSettle();
    expect(find.text('C'), findsNothing);
    expect(api.listChildrenCalls, 2, reason: 'collapse keeps the page cache');
  });

  testWidgets('medium shows an inline inspector after selection', (
    tester,
  ) async {
    final fileA = fileEntry(_idA, 'A');
    final api = FakeSourcesApi()
      ..childrenByParent[''] = [fileA]
      ..detailsByEntry[fileA.sourceEntryId.value] = fakeDetail(
        id: fileA.sourceEntryId.value,
        name: 'A',
      );
    await pumpBrowser(tester, api, width: 700);

    expect(find.text('Entry details'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('hierarchy-row-$_idA')));
    await tester.pumpAndSettle();
    expect(find.text('Entry details'), findsOneWidget);
    expect(find.text('A'), findsWidgets);
    expect(find.text('File'), findsWidgets);
  });

  testWidgets(
    'compact selection opens a transient inspector and restores focus',
    (tester) async {
      final fileA = fileEntry(_idA, 'A');
      final api = FakeSourcesApi()
        ..childrenByParent[''] = [fileA]
        ..detailsByEntry[fileA.sourceEntryId.value] = fakeDetail(
          id: fileA.sourceEntryId.value,
          name: 'A',
        );
      await pumpBrowser(tester, api, width: 400);

      await tester.tap(find.byKey(const ValueKey('hierarchy-row-$_idA')));
      await tester.pumpAndSettle();
      expect(find.text('Entry details'), findsOneWidget);

      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();
      expect(find.text('Entry details'), findsNothing);
      final rowFocus = tester
          .widget<Focus>(find.byKey(const ValueKey('focus-hierarchy-$_idA')))
          .focusNode!;
      expect(
        rowFocus.hasFocus,
        isTrue,
        reason: 'focus returns to the source row',
      );
    },
  );

  testWidgets('keyboard tree navigation is complete', (tester) async {
    final dirA = dirEntry(_idA, 'A');
    final fileB = fileEntry(_idB, 'B');
    final api = FakeSourcesApi()
      ..childrenByParent[''] = [dirA, fileB]
      ..childrenByParent[dirA.sourceEntryId.value] = [fileEntry(_idC, 'C')]
      ..detailsByEntry[fileB.sourceEntryId.value] = fakeDetail(
        id: fileB.sourceEntryId.value,
        name: 'B',
      );
    await pumpBrowser(tester, api, width: 1200);

    final firstFocus = tester
        .widget<Focus>(find.byKey(const ValueKey('focus-entry-$_idA')))
        .focusNode!;
    firstFocus.requestFocus();
    await tester.pump();
    expect(firstFocus.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final secondFocus = tester
        .widget<Focus>(find.byKey(const ValueKey('focus-entry-$_idB')))
        .focusNode!;
    expect(secondFocus.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(firstFocus.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('C'), findsOneWidget, reason: 'Right expands a container');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(
      find.text('C'),
      findsNothing,
      reason: 'Left collapses the container',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      find.text('Entry details'),
      findsOneWidget,
      reason: 'Enter activates the focused row',
    );
  });

  testWidgets('tree rows expose expanded and selected semantics', (
    tester,
  ) async {
    final dirA = dirEntry(_idA, 'A');
    final api = FakeSourcesApi()
      ..childrenByParent[''] = [dirA]
      ..childrenByParent[dirA.sourceEntryId.value] = [fileEntry(_idC, 'C')]
      ..detailsByEntry[dirA.sourceEntryId.value] = fakeDetail(
        id: dirA.sourceEntryId.value,
        name: 'A',
      );
    await pumpBrowser(tester, api, width: 1200);

    Semantics rowSemantics() => tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('hierarchy-row-$_idA')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(rowSemantics().properties.expanded, isFalse);
    expect(rowSemantics().properties.selected, isFalse);

    await tester.tap(find.byKey(const ValueKey('hierarchy-row-$_idA')));
    await tester.pumpAndSettle();
    expect(rowSemantics().properties.expanded, isTrue);
    expect(rowSemantics().properties.selected, isTrue);
  });

  testWidgets('Load More is keyboard reachable and activates', (tester) async {
    final api = FakeSourcesApi()
      ..childrenByParent[''] = numberedEntriesForPresentation(105);
    await pumpBrowser(tester, api, width: 1200, height: 9000);

    final footerFocus = tester
        .widget<Focus>(find.byKey(const ValueKey('focus-footer-')))
        .focusNode!;
    footerFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(api.listChildrenCalls, 2, reason: 'Enter activates Load More');
    expect(
      find.text('Load more entries'),
      findsNothing,
      reason: 'the page is complete after the final append',
    );
  });

  testWidgets('no provenance or status text is rendered', (tester) async {
    final api = FakeSourcesApi()
      ..childrenByParent[''] = [fileEntry(_idA, 'a.bin')];
    await pumpBrowser(tester, api, width: 1200);

    expect(find.textContaining('lastObserved'), findsNothing);
    expect(find.textContaining('locator'), findsNothing);
    expect(find.textContaining('fingerprint'), findsNothing);
    expect(find.textContaining('scan id'), findsNothing);
  });

  testWidgets(
    '2.0x text scale keeps compact controls reachable without clipping',
    (tester) async {
      final api = FakeSourcesApi()
        ..childrenByParent[''] = [dirEntry(_idA, 'A'), fileEntry(_idB, 'B')];
      await pumpBrowser(tester, api, width: 400, height: 900, textScale: 2.0);

      expect(tester.takeException(), isNull);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('hierarchy-back'))).width,
        greaterThan(0),
      );
    },
  );

  testWidgets('2.0x text scale keeps the large tree usable', (tester) async {
    final api = FakeSourcesApi()
      ..childrenByParent[''] = [dirEntry(_idA, 'A'), fileEntry(_idB, 'B')];
    await pumpBrowser(tester, api, width: 1200, height: 900, textScale: 2.0);

    expect(tester.takeException(), isNull);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
  });
}

List<SourceEntry> numberedEntriesForPresentation(int count) => [
  for (var index = 0; index < count; index++)
    fakeEntry(
      id: (index + 1).toRadixString(16).padLeft(32, '0'),
      name: 'entry$index',
    ),
];
