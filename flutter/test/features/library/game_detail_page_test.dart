import 'dart:async';

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
        librarySourceId: const LibrarySourceId(
          '55555555555555555555555555555555',
        ),
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
          derivedFingerprint: null,
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
        demandSource: _emptyDemandSource,
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
      expect(find.text('Inactive orphan'), findsWidgets);
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
      demandSource: _emptyDemandSource,
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
      demandSource: _emptyDemandSource,
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
      demandSource: _emptyDemandSource,
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

  testWidgets(
    'retains loaded detail and uses bounded artwork decode targets while refreshing',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 1000);
      addTearDown(tester.view.reset);

      final gameId = const GameId('88888888888888888888888888888888');
      final initial = gameDetail(
        id: gameId.value,
        title: 'Refreshable detail',
        artwork: const [
          ResolvedArtwork(
            artworkType: 'cover_front',
            referenceId: 'cover-reference',
            assetId: 'asset-a',
            ordering: 0,
            selectionReason: 'test',
            resolutionRevision: 1,
            resolvedAt: 1,
          ),
        ],
      );
      final updated = gameDetail(id: gameId.value, title: 'Updated detail');
      final gate = Completer<GetGameResult>();
      var calls = 0;
      final games = FakeGamesApi()
        ..onGetGame = (_) {
          calls++;
          if (calls == 1) return GetGameFound(initial);
          return gate.future;
        };
      final artwork = FakeArtworkApi()
        ..assets['asset-a'] = ArtworkAssetBytes(
          assetId: 'asset-a',
          bytes: _onePixelPng,
          mimeType: 'image/png',
          width: 1,
          height: 1,
        );
      final controller = GameDetailController(
        games: games,
        gameId: gameId,
        runtimeContext: readyLibraryRuntimeContext,
        demandSource: _emptyDemandSource,
      );
      await controller.initialize();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _detailHarness(
          gameId: gameId,
          controller: controller,
          artwork: artwork,
        ),
      );
      await tester.pumpAndSettle();

      final image = tester.widget<Image>(find.byType(Image).first);
      final resized = image.image as ResizeImage;
      expect(resized.width, 180);
      expect(resized.height, 240);

      final reload = controller.reload();
      await tester.pump();
      expect(find.text('Refreshable detail'), findsWidgets);
      expect(
        find.byKey(const ValueKey<String>('game-detail-refreshing')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);

      gate.complete(GetGameFound(updated));
      await reload;
      await tester.pumpAndSettle();
      expect(find.text('Updated detail'), findsWidgets);
    },
  );

  testWidgets('shows a retained-detail refresh failure with retry', (
    tester,
  ) async {
    final gameId = const GameId('12121212121212121212121212121212');
    final initial = gameDetail(id: gameId.value, title: 'Retained detail');
    final updated = gameDetail(id: gameId.value, title: 'Retried detail');
    var calls = 0;
    final games = FakeGamesApi()
      ..onGetGame = (_) {
        calls++;
        return switch (calls) {
          1 => GetGameFound(initial),
          2 => Future<GetGameResult>.error(
            const TransportFailure('refresh failed'),
          ),
          _ => GetGameFound(updated),
        };
      };
    final controller = GameDetailController(
      games: games,
      gameId: gameId,
      runtimeContext: readyLibraryRuntimeContext,
      demandSource: _emptyDemandSource,
    );
    await controller.initialize();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _detailHarness(gameId: gameId, controller: controller),
    );
    await tester.pumpAndSettle();

    await controller.reload();
    await tester.pumpAndSettle();
    expect(find.text('Retained detail'), findsWidgets);
    expect(find.text('refresh failed'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('game-detail-refresh-failure')),
      findsOneWidget,
    );
    final failureMessageSemantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.text('refresh failed'),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(failureMessageSemantics.properties.liveRegion, isTrue);

    await tester.tap(
      find.byKey(const ValueKey<String>('game-detail-refresh-retry')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retried detail'), findsWidgets);
    expect(find.text('refresh failed'), findsNothing);
  });

  testWidgets('recreates artwork cache when the artwork API changes', (
    tester,
  ) async {
    final gameId = const GameId('99999999999999999999999999999999');
    final detail = gameDetail(
      id: gameId.value,
      artwork: const [
        ResolvedArtwork(
          artworkType: 'cover_front',
          referenceId: 'cover-reference',
          assetId: 'asset-a',
          ordering: 0,
          selectionReason: 'test',
          resolutionRevision: 1,
          resolvedAt: 1,
        ),
      ],
    );
    final controller = GameDetailController(
      games: FakeGamesApi()..result = GetGameFound(detail),
      gameId: gameId,
      runtimeContext: readyLibraryRuntimeContext,
      demandSource: _emptyDemandSource,
    );
    await controller.initialize();
    addTearDown(controller.dispose);
    final firstArtwork = FakeArtworkApi()
      ..assets['asset-a'] = ArtworkAssetBytes(
        assetId: 'asset-a',
        bytes: _onePixelPng,
        mimeType: 'image/png',
        width: 1,
        height: 1,
      );
    final secondArtwork = FakeArtworkApi()
      ..assets['asset-a'] = ArtworkAssetBytes(
        assetId: 'asset-a',
        bytes: _onePixelPng,
        mimeType: 'image/png',
        width: 1,
        height: 1,
      );
    ArtworkApiHolder.initial = firstArtwork;
    final artworkProvider = NotifierProvider<ArtworkApiHolder, ArtworkApi>(
      ArtworkApiHolder.new,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameDetailControllerProvider(gameId).overrideWithValue(controller),
          libraryArtworkApiProvider.overrideWith(
            (ref) => ref.watch(artworkProvider),
          ),
        ],
        child: MaterialApp(
          home: GameDetailPage(
            gameId: gameId,
            onMissingGame: () {},
            onOpenGame: (_) {},
            onOpenJob: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(firstArtwork.callsByAsset['asset-a'], 1);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(GameDetailPage)),
    );
    container.read(artworkProvider.notifier).replace(secondArtwork);
    await tester.pumpAndSettle();
    expect(secondArtwork.callsByAsset['asset-a'], 1);
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

const _emptyDemandSource = LibraryReconciliationDemandSource(
  Stream<LibraryReconciliationDemand>.empty(),
);

const _onePixelPng = <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  248,
  207,
  192,
  240,
  31,
  0,
  5,
  0,
  1,
  255,
  137,
  153,
  61,
  29,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];

final class ArtworkApiHolder extends Notifier<ArtworkApi> {
  static ArtworkApi? initial;

  @override
  ArtworkApi build() => initial!;

  void replace(ArtworkApi value) {
    state = value;
  }
}
