import 'package:argus/core/client/client.dart';
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
}
