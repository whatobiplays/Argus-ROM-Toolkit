import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../sources/sources_test_fakes.dart';
import 'library_test_fakes.dart';

void main() {
  test('Library width bands honor every exact contract boundary', () {
    expect(libraryWidthClassForWidth(599), LibraryWidthClass.compact);
    expect(libraryWidthClassForWidth(600), LibraryWidthClass.medium);
    expect(libraryWidthClassForWidth(839), LibraryWidthClass.medium);
    expect(libraryWidthClassForWidth(840), LibraryWidthClass.expanded);
    expect(libraryWidthClassForWidth(1199), LibraryWidthClass.expanded);
    expect(libraryWidthClassForWidth(1200), LibraryWidthClass.large);
  });

  testWidgets('renders bounded rows and compact controls at 2x text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(599, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final reads = FakeLibraryReads();
    reads.onListGames = (_) => GamePage(items: [libraryRow()]);
    final controller = await _readyController(reads);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _libraryHarness(
        controller: controller,
        textScaler: const TextScaler.linear(2),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('library-search')),
      findsOneWidget,
    );
    expect(find.text('Search Library'), findsOneWidget);
    expect(find.text('Test Game'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('library-refresh-selected')),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('grid card controls are not clipped by their Stack', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final reads = FakeLibraryReads()
      ..onListGames = (_) => GamePage(items: [libraryRow()]);
    final controller = await _readyController(reads);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_libraryHarness(controller: controller));
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<Stack>(find.byType(Stack))
          .any((stack) => stack.clipBehavior == Clip.none),
      isTrue,
    );
  });

  testWidgets('library refresh fake failures reach the toolbar error path', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final reads = FakeLibraryReads()
      ..onListGames = (_) => GamePage(items: [libraryRow()]);
    final refresh = FakeLibraryRefreshApi()
      ..failure = const TransportFailure('refresh failed');
    final controller = await _readyController(reads, refreshApi: refresh);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _libraryHarness(controller: controller, refreshApi: refresh),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('library-refresh')));
    await tester.pump();

    expect(find.text('refresh failed'), findsOneWidget);
    expect(refresh.failure, isNull);
  });
}

Future<LibraryController> _readyController(
  FakeLibraryReads reads, {
  FakeLibraryRefreshApi? refreshApi,
}) async {
  final controller = LibraryController(
    reads: reads,
    sources: FakeSourcesApi(),
    refreshApi: refreshApi ?? FakeLibraryRefreshApi(),
    gamesApi: FakeGamesApi(),
    scope: const LibraryScope.platform('nintendo.nes'),
    runtimeContext: readyLibraryRuntimeContext,
    demandSource: const LibraryReconciliationDemandSource(
      Stream<LibraryReconciliationDemand>.empty(),
    ),
  );
  await controller.initialize();
  return controller;
}

Widget _libraryHarness({
  required LibraryController controller,
  TextScaler? textScaler,
  LibraryRefreshApi? refreshApi,
}) => ProviderScope(
  overrides: [
    libraryControllerProvider(
      controller.state.scope,
    ).overrideWithValue(controller),
    if (refreshApi != null)
      libraryRefreshApiProvider.overrideWithValue(refreshApi),
  ],
  child: MediaQuery(
    data: MediaQueryData(textScaler: textScaler ?? const TextScaler.linear(1)),
    child: MaterialApp(
      home: LibraryPage(
        scope: controller.state.scope,
        onOpenAll: () {},
        onOpenSources: () {},
        onOpenGame: (_) {},
        onOpenJob: (_) {},
      ),
    ),
  ),
);
