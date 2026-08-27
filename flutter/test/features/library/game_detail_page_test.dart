import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'library_test_fakes.dart';

void main() {
  test('detail width bands honor every exact contract boundary', () {
    expect(gameDetailWidthClassForWidth(599), GameDetailWidthClass.compact);
    expect(gameDetailWidthClassForWidth(600), GameDetailWidthClass.medium);
    expect(gameDetailWidthClassForWidth(839), GameDetailWidthClass.medium);
    expect(gameDetailWidthClassForWidth(840), GameDetailWidthClass.expanded);
    expect(gameDetailWidthClassForWidth(1199), GameDetailWidthClass.expanded);
    expect(gameDetailWidthClassForWidth(1200), GameDetailWidthClass.large);
  });

  testWidgets(
    'renders safe detail sections, orphan status, and advanced Force action',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 1000);
      addTearDown(tester.view.reset);

      final gameId = GameId('11111111111111111111111111111111');
      final contentId = ContentId('22222222222222222222222222222222');
      final source = GameContentSourceSummary(
        sourceEntryId: SourceEntryId('33333333333333333333333333333333'),
        librarySourceId: 'local-source',
        sourceDisplayName: 'Local library',
        libraryRootId: LibraryRootId('44444444444444444444444444444444'),
        rootDisplayName: 'Games',
        safeLocationPresentation: 'SNES/Example.sfc',
      );
      final content = ContentSummary(
        gameContentId: contentId,
        platformId: PlatformId.nintendoSnes,
        contentType: ContentType.opticalDiscCd,
        presence: ContentPresence.available,
        identification: IdentificationState.identified,
        sourceCount: 2,
        identity: const ContentIdentitySummary(
          schemeId: 'sha256',
          revision: 1,
          digest: 'safe-digest',
        ),
        provenance: ContentProvenanceSummary(
          sourceEntryId: source.sourceEntryId,
          associationKey: 'safe-association',
          sourceFingerprint: 'safe-fingerprint',
          lastObservedScanId: 'safe-scan',
        ),
        sources: [source],
      );
      final detail = gameDetail(
        id: gameId.value,
        lifecycle: GameLifecycle.inactiveOrphan,
        metadata: resolvedMetadata(title: 'Resolved Example'),
        content: [content],
        memberships: [
          GameMembershipSummary(
            gameContentId: contentId,
            relationship: MembershipRelationship.disc,
            groupingBasis: GroupingBasis.explicitRelationshipEvidence,
            groupingRevision: 2,
          ),
        ],
        artwork: const [
          ResolvedArtwork(
            artworkType: 'cover_front',
            referenceId: 'safe-artwork-reference',
            assetId: null,
            ordering: 0,
            selectionReason: 'selected by canonical resolver',
            resolutionRevision: 1,
            resolvedAt: 1,
          ),
        ],
      );
      final games = FakeGamesApi()..result = GetGameFound(detail);
      final controller = GameDetailController(
        games: games,
        gameId: gameId,
        runtimeContext: readyLibraryRuntimeContext,
      );
      await controller.initialize();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _detailHarness(
          gameId: gameId,
          controller: controller,
          artwork: FakeArtworkApi(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Overview'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('game-overview-title')),
        findsOneWidget,
      );
      expect(find.text('Resolved Example'), findsWidgets);
      expect(
        find.text(
          'This inactive orphan is retained for historical inspection and is read-only.',
        ),
        findsOneWidget,
      );
      expect(find.text('Achievements'), findsNothing);
      expect(find.text('Edit metadata'), findsNothing);
      expect(find.text('Force Refresh'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('game-force-refresh')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Force Refresh'), findsOneWidget);
      await tester.tap(find.text('Force Refresh'));
      await tester.pump();
      expect(games.refreshedGameIds, [gameId]);
      expect(games.refreshModes, [RefreshMode.force]);

      for (final title in [
        'Metadata',
        'Files & Copies',
        'Sources / Availability',
        'Activity / History',
        'Technical provenance',
      ]) {
        await _scrollTo(
          tester,
          find.byKey(ValueKey<String>('game-section-$title')),
        );
        expect(find.text(title), findsOneWidget);
      }

      await _scrollTo(
        tester,
        find.byKey(const ValueKey<String>('game-section-Artwork')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('game-section-Artwork')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Front cover'), findsOneWidget);
      expect(find.text('Artwork not downloaded'), findsWidgets);
    },
  );

  testWidgets('compact detail remains usable at 2x text scale', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(599, 1000);
    addTearDown(tester.view.reset);

    final gameId = GameId('77777777777777777777777777777777');
    final games = FakeGamesApi()
      ..result = GetGameFound(
        gameDetail(
          id: gameId.value,
          metadata: resolvedMetadata(title: 'Compact Detail'),
        ),
      );
    final controller = GameDetailController(
      games: games,
      gameId: gameId,
      runtimeContext: readyLibraryRuntimeContext,
    );
    await controller.initialize();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _detailHarness(
        gameId: gameId,
        controller: controller,
        textScaler: const TextScaler.linear(2),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Compact Detail'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('redirect and typed not-found states remain explicit', (
    tester,
  ) async {
    final requested = GameId('55555555555555555555555555555555');
    final canonical = GameId('66666666666666666666666666666666');
    final games = FakeGamesApi()..result = GetGameRedirected(canonical);
    final redirectController = GameDetailController(
      games: games,
      gameId: requested,
      runtimeContext: readyLibraryRuntimeContext,
    );
    await redirectController.initialize();
    addTearDown(redirectController.dispose);
    var openedCanonical = false;

    await tester.pumpWidget(
      _detailHarness(
        gameId: requested,
        controller: redirectController,
        onOpenGame: (id) => openedCanonical = id == canonical,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('This Game has moved.'), findsOneWidget);
    await tester.tap(find.text('Open canonical Game'));
    expect(openedCanonical, isTrue);

    final missingGames = FakeGamesApi()..getFailure = gameNotFoundFailure();
    final missingController = GameDetailController(
      games: missingGames,
      gameId: requested,
      runtimeContext: readyLibraryRuntimeContext,
    );
    await missingController.initialize();
    addTearDown(missingController.dispose);
    var returnedToLibrary = false;

    await tester.pumpWidget(
      _detailHarness(
        gameId: requested,
        controller: missingController,
        onMissingGame: () => returnedToLibrary = true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Game not found'), findsOneWidget);
    await tester.tap(find.text('Back to Library'));
    expect(returnedToLibrary, isTrue);
  });
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    400,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}

Widget _detailHarness({
  required GameId gameId,
  required GameDetailController controller,
  ArtworkApi? artwork,
  TextScaler? textScaler,
  void Function(GameId gameId)? onOpenGame,
  VoidCallback? onMissingGame,
}) => ProviderScope(
  overrides: [
    gameDetailControllerProvider(gameId).overrideWithValue(controller),
    libraryArtworkApiProvider.overrideWithValue(artwork ?? FakeArtworkApi()),
  ],
  child: MediaQuery(
    data: MediaQueryData(textScaler: textScaler ?? const TextScaler.linear(1)),
    child: MaterialApp(
      home: GameDetailPage(
        gameId: gameId,
        onMissingGame: onMissingGame ?? () {},
        onOpenGame: onOpenGame ?? (_) {},
        onOpenJob: (_) {},
      ),
    ),
  ),
);
