import 'package:argus/core/client/client.dart';
import 'package:argus/features/sources/application/local_filesystem_browser_controller.dart';
import 'package:argus/features/sources/presentation/local_filesystem_browser.dart';
import 'package:argus/features/sources/presentation/selected_library_folder.dart';
import 'package:argus/features/sources/sources_composition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sources_test_fakes.dart';

const _rootLocation = LocalFilesystemBrowseLocation('root');
const _fixtureLocation = LocalFilesystemBrowseLocation('fixture');

LocalFilesystemBrowseRoot _root() => const LocalFilesystemBrowseRoot(
  location: _rootLocation,
  displayName: 'Internal storage',
  safeLocationPresentation: 'Internal storage',
);

LocalFilesystemBrowsePage _rootPage() => const LocalFilesystemBrowsePage(
  current: LocalFilesystemBrowseRoot(
    location: _rootLocation,
    displayName: 'Internal storage',
    safeLocationPresentation: 'Internal storage',
  ),
  breadcrumbs: [
    LocalFilesystemBrowseBreadcrumb(
      location: _rootLocation,
      displayName: 'Internal storage',
    ),
  ],
  directories: [
    LocalFilesystemBrowseDirectory(
      location: _fixtureLocation,
      displayName: 'ArgusP02002Fixture',
    ),
  ],
  nextCursor: null,
);

LocalFilesystemBrowsePage _fixturePage() => const LocalFilesystemBrowsePage(
  current: LocalFilesystemBrowseRoot(
    location: _fixtureLocation,
    displayName: 'ArgusP02002Fixture',
    safeLocationPresentation: 'Internal storage / ArgusP02002Fixture',
  ),
  breadcrumbs: [
    LocalFilesystemBrowseBreadcrumb(
      location: _rootLocation,
      displayName: 'Internal storage',
    ),
    LocalFilesystemBrowseBreadcrumb(
      location: _fixtureLocation,
      displayName: 'ArgusP02002Fixture',
    ),
  ],
  directories: [],
  nextCursor: null,
);

ProviderContainer _container(FakeSourcesApi api) {
  final container = ProviderContainer(
    overrides: [sourcesApiProvider.overrideWithValue(api)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  testWidgets(
    'browser navigates backend locations and returns opaque selection',
    (tester) async {
      final api = FakeSourcesApi()
        ..browseRoots = [_root()]
        ..browsePages['root|'] = _rootPage()
        ..browsePages['fixture|'] = _fixturePage();
      final container = _container(api);
      SelectedLibraryFolder? selected;
      var cancelled = false;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: LocalFilesystemBrowser(
                onSelected: (value) => selected = value,
                onCancel: () => cancelled = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rootKey = const ValueKey<String>('local-browser-root-root');
      await tester.tap(find.byKey(rootKey));
      await tester.pumpAndSettle();
      final fixtureKey = const ValueKey<String>(
        'local-browser-directory-fixture',
      );
      await tester.tap(find.byKey(fixtureKey));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('local-browser-up')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey<String>('local-browser-up')));
      await tester.pumpAndSettle();
      expect(find.byKey(fixtureKey), findsOneWidget);

      await tester.tap(find.byKey(fixtureKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('local-browser-select-folder')),
      );

      expect(cancelled, isFalse);
      expect(selected, isNotNull);
      expect(selected!.selection, isA<LocalFilesystemRootSelectionProvider>());
      expect(
        (selected!.selection as LocalFilesystemRootSelectionProvider)
            .selectionIdentity,
        'fixture',
      );
      expect(selected!.displayName, 'ArgusP02002Fixture');
      expect(
        selected!.safeLocationPresentation,
        'Internal storage / ArgusP02002Fixture',
      );
    },
  );

  testWidgets(
    'reopened browser exposes the provider directory again after dismissal',
    (tester) async {
      final api = FakeSourcesApi()
        ..browseRoots = [_root()]
        ..browsePages['root|'] = _rootPage();
      final container = _container(api);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (dialogContext) => Dialog(
                      child: LocalFilesystemBrowser(
                        onSelected: _ignoreSelection,
                        onCancel: () => Navigator.of(dialogContext).pop(),
                      ),
                    ),
                  ),
                  child: const Text('Open picker'),
                ),
              ),
            ),
          ),
        ),
      );

      Future<void> openAndDismissAtRoot() async {
        await tester.tap(find.text('Open picker'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('local-browser-root-root')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('local-browser-directory-fixture')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('local-browser-cancel')),
        );
        await tester.pumpAndSettle();
      }

      await openAndDismissAtRoot();
      await openAndDismissAtRoot();
      expect(
        find.byKey(const ValueKey<String>('local-browser-surface')),
        findsNothing,
      );
    },
  );

  testWidgets('browser Cancel delegates dismissal without a selection', (
    tester,
  ) async {
    final api = FakeSourcesApi()..browseRoots = [_root()];
    final container = _container(api);
    var cancelled = false;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: LocalFilesystemBrowser(
              onSelected: (_) {},
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('local-browser-cancel')),
    );
    expect(cancelled, isTrue);
  });

  testWidgets(
    'system Back dismisses at the volume list and retreats while browsing',
    (tester) async {
      final api = FakeSourcesApi()
        ..browseRoots = [_root()]
        ..browsePages['root|'] = _rootPage()
        ..browsePages['fixture|'] = _fixturePage();
      final container = _container(api);
      var cancelled = false;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: LocalFilesystemBrowser(
                onSelected: (_) {},
                onCancel: () => cancelled = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      PopScope<void> popScope() =>
          tester.widget<PopScope<void>>(find.byType(PopScope<void>));

      expect(popScope().canPop, isTrue);

      await tester.tap(
        find.byKey(const ValueKey<String>('local-browser-root-root')),
      );
      await tester.pumpAndSettle();
      expect(popScope().canPop, isFalse);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('local-browser-root-root')),
        findsOneWidget,
      );
      expect(popScope().canPop, isTrue);
      expect(cancelled, isFalse);
    },
  );

  testWidgets(
    'browse failure preserves the current page and exposes an exact retry',
    (tester) async {
      final api = FakeSourcesApi()
        ..browseRoots = [_root()]
        ..browsePages['root|'] = _rootPage();
      final container = _container(api);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: LocalFilesystemBrowser(onSelected: (_) {}, onCancel: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('local-browser-root-root')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('local-browser-directory-fixture')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Internal storage'), findsWidgets);
      expect(find.text('Could not load this folder'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('local-browser-browse-retry')),
        findsOneWidget,
      );

      api.browsePages['fixture|'] = _fixturePage();
      await tester.tap(
        find.byKey(const ValueKey<String>('local-browser-browse-retry')),
      );
      await tester.pumpAndSettle();

      expect(find.text('ArgusP02002Fixture'), findsWidgets);
      expect(find.text('Could not load this folder'), findsNothing);
    },
  );

  testWidgets(
    'picker surface stays above a supplied IME inset at compact width',
    (tester) async {
      final api = FakeSourcesApi()..browseRoots = [_root()];
      final container = _container(api);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 640),
                viewInsets: EdgeInsets.only(bottom: 220),
                textScaler: TextScaler.linear(2),
              ),
              child: const SizedBox(
                width: 320,
                height: 640,
                child: Material(
                  child: LocalFilesystemBrowser(
                    onSelected: _ignoreSelection,
                    onCancel: _ignoreCancel,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surface = tester.getRect(
        find.byKey(const ValueKey<String>('local-browser-surface')),
      );
      expect(surface.bottom, lessThanOrEqualTo(420));
      expect(find.text('Internal storage'), findsWidgets);
    },
  );

  testWidgets('picker surface remains bounded in a short compact 2x dialog', (
    tester,
  ) async {
    final api = FakeSourcesApi()
      ..browseRoots = [_root()]
      ..browsePages['root|'] = _rootPage()
      ..browsePages['fixture|'] = _fixturePage();
    final container = _container(api);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(411, 300),
              textScaler: TextScaler.linear(2),
            ),
            child: SizedBox(
              width: 411,
              height: 300,
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    body: Builder(
                      builder: (context) => ElevatedButton(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => const Dialog(
                            child: SizedBox(
                              height: 140,
                              child: LocalFilesystemBrowser(
                                onSelected: _ignoreSelection,
                                onCancel: _ignoreCancel,
                              ),
                            ),
                          ),
                        ),
                        child: const Text('Open picker'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    final controller = container.read(
      localFilesystemBrowserControllerProvider.notifier,
    );
    await controller.openRoot(_root());
    await controller.openDirectory(_rootPage().directories.single);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('local-browser-select-folder')),
    );

    expect(tester.takeException(), isNull);
  });
}

void _ignoreSelection(SelectedLibraryFolder _) {}

void _ignoreCancel() {}
