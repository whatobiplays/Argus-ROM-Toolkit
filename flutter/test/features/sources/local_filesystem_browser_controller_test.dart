import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:argus/features/sources/application/local_filesystem_browser_controller.dart';
import 'package:argus/features/sources/application/sources_state.dart';
import 'package:argus/features/sources/sources_composition.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads mounted roots and opens provider-owned locations', () async {
    final api = _BrowserFakeApi();
    final container = ProviderContainer(
      overrides: [sourcesApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      localFilesystemBrowserControllerProvider.notifier,
    );

    await controller.load();
    expect(container.read(localFilesystemBrowserControllerProvider).roots, [
      api.root,
    ]);

    await controller.openRoot(api.root);
    expect(
      container
          .read(localFilesystemBrowserControllerProvider)
          .page
          ?.current
          .location
          .value,
      'root-location',
    );
    await controller.openDirectory(api.child);
    expect(
      container
          .read(localFilesystemBrowserControllerProvider)
          .page
          ?.current
          .location
          .value,
      'child-location',
    );
    expect(api.requests.map((request) => request.location), [
      'root-location',
      'child-location',
    ]);
  });

  test(
    'back follows backend breadcrumbs and returns dismiss at volume list',
    () async {
      final api = _BrowserFakeApi();
      final container = ProviderContainer(
        overrides: [sourcesApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        localFilesystemBrowserControllerProvider.notifier,
      );
      await controller.load();
      await controller.openRoot(api.root);
      await controller.openDirectory(api.child);

      expect(await controller.back(), isTrue);
      expect(
        container
            .read(localFilesystemBrowserControllerProvider)
            .page
            ?.current
            .location
            .value,
        'root-location',
      );
      expect(await controller.back(), isTrue);
      expect(
        container.read(localFilesystemBrowserControllerProvider).page,
        isNull,
      );
      expect(await controller.back(), isFalse);
    },
  );

  test(
    'load more uses the backend cursor and preserves returned rows',
    () async {
      final api = _BrowserFakeApi(withNextPage: true);
      final container = ProviderContainer(
        overrides: [sourcesApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        localFilesystemBrowserControllerProvider.notifier,
      );
      await controller.openRoot(api.root);
      await controller.loadMore();

      final state = container.read(localFilesystemBrowserControllerProvider);
      expect(state.page?.directories.map((entry) => entry.displayName), [
        'first',
        'second',
      ]);
      expect(api.requests.last.cursor, 'next-cursor');
    },
  );

  test('retry repeats the exact failed browse request', () async {
    final api = _BrowserFakeApi(failNextBrowse: true);
    final container = ProviderContainer(
      overrides: [sourcesApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      localFilesystemBrowserControllerProvider.notifier,
    );
    await controller.openRoot(api.root);
    expect(
      container.read(localFilesystemBrowserControllerProvider).failure,
      isA<ClientFailure>(),
    );

    await controller.retry();
    expect(
      container.read(localFilesystemBrowserControllerProvider).failure,
      isNull,
    );
    expect(api.requests.map((request) => request.cursor), [null, null]);
  });

  test(
    'lifecycle reconciliation refreshes the current browser location',
    () async {
      final api = _BrowserFakeApi();
      final demands = StreamController<SourcesReconciliationDemand>.broadcast();
      final container = ProviderContainer(
        overrides: [
          sourcesApiProvider.overrideWithValue(api),
          sourcesReconciliationDemandProvider.overrideWithValue(
            SourcesReconciliationDemandSource(demands.stream),
          ),
        ],
      );
      addTearDown(demands.close);
      addTearDown(container.dispose);
      final observation = container.listen(
        localFilesystemBrowserControllerProvider,
        (previous, next) {},
      );
      addTearDown(observation.close);
      final controller = container.read(
        localFilesystemBrowserControllerProvider.notifier,
      );

      await controller.load();
      await controller.openRoot(api.root);
      await controller.openDirectory(api.child);
      final requestsBeforeDemand = api.requests.length;

      demands.add(const SourcesReconciliationDemand.lifecycleChanged());
      await Future<void>.delayed(Duration.zero);

      expect(api.requests.length, requestsBeforeDemand + 1);
      expect(api.requests.last.location, 'child-location');
      expect(
        container
            .read(localFilesystemBrowserControllerProvider)
            .page
            ?.current
            .location
            .value,
        'child-location',
      );
    },
  );

  test(
    'lifecycle reconciliation retries after an in-flight root browse load',
    () async {
      final api = _BrowserFakeApi();
      final demands = StreamController<SourcesReconciliationDemand>.broadcast();
      final container = ProviderContainer(
        overrides: [
          sourcesApiProvider.overrideWithValue(api),
          sourcesReconciliationDemandProvider.overrideWithValue(
            SourcesReconciliationDemandSource(demands.stream),
          ),
        ],
      );
      addTearDown(demands.close);
      addTearDown(container.dispose);
      final observation = container.listen(
        localFilesystemBrowserControllerProvider,
        (previous, next) {},
      );
      addTearDown(observation.close);
      final controller = container.read(
        localFilesystemBrowserControllerProvider.notifier,
      );

      await controller.load();
      final gate = Completer<void>();
      api.browseGates.add(gate);
      final opening = controller.openRoot(api.root);
      await Future<void>.delayed(Duration.zero);

      demands.add(const SourcesReconciliationDemand.lifecycleChanged());
      gate.complete();
      await opening;
      await _settle();

      expect(api.requests.map((request) => request.location), [
        'root-location',
        'root-location',
      ]);
    },
  );

  test(
    'lifecycle reconciliation retries after an in-flight directory load',
    () async {
      final api = _BrowserFakeApi();
      final demands = StreamController<SourcesReconciliationDemand>.broadcast();
      final container = ProviderContainer(
        overrides: [
          sourcesApiProvider.overrideWithValue(api),
          sourcesReconciliationDemandProvider.overrideWithValue(
            SourcesReconciliationDemandSource(demands.stream),
          ),
        ],
      );
      addTearDown(demands.close);
      addTearDown(container.dispose);
      final observation = container.listen(
        localFilesystemBrowserControllerProvider,
        (previous, next) {},
      );
      addTearDown(observation.close);
      final controller = container.read(
        localFilesystemBrowserControllerProvider.notifier,
      );

      await controller.openRoot(api.root);
      final gate = Completer<void>();
      api.browseGates.add(gate);
      final opening = controller.openDirectory(api.child);
      await Future<void>.delayed(Duration.zero);

      demands.add(const SourcesReconciliationDemand.lifecycleChanged());
      gate.complete();
      await opening;
      await _settle();

      expect(api.requests.map((request) => request.location), [
        'root-location',
        'child-location',
        'child-location',
      ]);
    },
  );

  test(
    'disposal ignores reconciliation queued by an in-flight browse load',
    () async {
      final api = _BrowserFakeApi();
      final demands = StreamController<SourcesReconciliationDemand>.broadcast();
      final container = ProviderContainer(
        overrides: [
          sourcesApiProvider.overrideWithValue(api),
          sourcesReconciliationDemandProvider.overrideWithValue(
            SourcesReconciliationDemandSource(demands.stream),
          ),
        ],
      );
      var disposed = false;
      addTearDown(() async {
        if (!disposed) {
          disposed = true;
          container.dispose();
        }
        await demands.close();
      });
      final observation = container.listen(
        localFilesystemBrowserControllerProvider,
        (previous, next) {},
      );
      addTearDown(observation.close);
      final controller = container.read(
        localFilesystemBrowserControllerProvider.notifier,
      );

      final gate = Completer<void>();
      api.browseGates.add(gate);
      final opening = controller.openRoot(api.root);
      await Future<void>.delayed(Duration.zero);

      demands.add(const SourcesReconciliationDemand.lifecycleChanged());
      await Future<void>.delayed(Duration.zero);
      disposed = true;
      container.dispose();

      gate.complete();
      await opening;
      await _settle();
    },
  );

  test(
    'disposal ignores a root-load failure after the request completes',
    () async {
      final api = _BrowserFakeApi();
      final container = ProviderContainer(
        overrides: [sourcesApiProvider.overrideWithValue(api)],
      );
      var disposed = false;
      addTearDown(() {
        if (!disposed) {
          disposed = true;
          container.dispose();
        }
      });
      final observation = container.listen(
        localFilesystemBrowserControllerProvider,
        (previous, next) {},
      );
      addTearDown(observation.close);
      final controller = container.read(
        localFilesystemBrowserControllerProvider.notifier,
      );

      final gate = Completer<void>();
      api.rootGates.add(gate);
      api.failNextRootLoad = true;
      final loading = controller.load();
      await Future<void>.delayed(Duration.zero);

      disposed = true;
      container.dispose();
      gate.complete();
      await loading;
      await _settle();
    },
  );

  test('back to the volume list invalidates an in-flight refresh', () async {
    final api = _BrowserFakeApi();
    final container = ProviderContainer(
      overrides: [sourcesApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final observation = container.listen(
      localFilesystemBrowserControllerProvider,
      (previous, next) {},
    );
    addTearDown(observation.close);
    final controller = container.read(
      localFilesystemBrowserControllerProvider.notifier,
    );

    await controller.openRoot(api.root);
    final gate = Completer<void>();
    api.browseGates.add(gate);
    final refreshing = controller.refresh();
    await Future<void>.delayed(Duration.zero);

    expect(await controller.back(), isTrue);
    expect(
      container.read(localFilesystemBrowserControllerProvider).page,
      isNull,
    );
    gate.complete();
    await refreshing;
    await _settle();

    final state = container.read(localFilesystemBrowserControllerProvider);
    expect(state.page, isNull);
    expect(state.loading, isFalse);
    expect(state.loadingMore, isFalse);
  });
}

Future<void> _settle() async {
  for (var index = 0; index < 10; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _BrowserFakeApi implements SourcesApi {
  _BrowserFakeApi({this.withNextPage = false, this.failNextBrowse = false});

  final bool withNextPage;
  bool failNextBrowse;
  final requests = <_BrowseRequest>[];
  final browseGates = <Completer<void>>[];
  final rootGates = <Completer<void>>[];
  bool failNextRootLoad = false;

  final root = const LocalFilesystemBrowseRoot(
    location: LocalFilesystemBrowseLocation('root-location'),
    displayName: 'Internal storage',
    safeLocationPresentation: 'Internal storage',
  );
  final child = const LocalFilesystemBrowseDirectory(
    location: LocalFilesystemBrowseLocation('child-location'),
    displayName: 'Games',
  );

  @override
  Future<List<LocalFilesystemBrowseRoot>>
  listLocalFilesystemBrowseRoots() async {
    if (rootGates.isNotEmpty) {
      await rootGates.removeAt(0).future;
    }
    if (failNextRootLoad) {
      failNextRootLoad = false;
      throw const TransportFailure('root browse failed');
    }
    return [root];
  }

  @override
  Future<LocalFilesystemBrowsePage> listLocalFilesystemBrowseDirectories({
    required LocalFilesystemBrowseLocation location,
    String? cursor,
    required int pageSize,
  }) async {
    requests.add(_BrowseRequest(location.value, cursor));
    if (browseGates.isNotEmpty) {
      await browseGates.removeAt(0).future;
    }
    if (failNextBrowse) {
      failNextBrowse = false;
      throw const TransportFailure('browse failed');
    }
    if (location.value == 'child-location') {
      return LocalFilesystemBrowsePage(
        current: LocalFilesystemBrowseRoot(
          location: location,
          displayName: 'Games',
          safeLocationPresentation: 'Internal storage / Games',
        ),
        breadcrumbs: [rootAsBreadcrumb, childAsBreadcrumb],
        directories: const [],
        nextCursor: null,
      );
    }
    final first = const LocalFilesystemBrowseDirectory(
      location: LocalFilesystemBrowseLocation('child-location'),
      displayName: 'first',
    );
    final second = const LocalFilesystemBrowseDirectory(
      location: LocalFilesystemBrowseLocation('second-location'),
      displayName: 'second',
    );
    return LocalFilesystemBrowsePage(
      current: root,
      breadcrumbs: const [rootAsBreadcrumb],
      directories: cursor == null ? [first] : [second],
      nextCursor: withNextPage && cursor == null ? 'next-cursor' : null,
    );
  }

  static const rootAsBreadcrumb = LocalFilesystemBrowseBreadcrumb(
    location: LocalFilesystemBrowseLocation('root-location'),
    displayName: 'Internal storage',
  );
  static const childAsBreadcrumb = LocalFilesystemBrowseBreadcrumb(
    location: LocalFilesystemBrowseLocation('child-location'),
    displayName: 'Games',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

final class _BrowseRequest {
  const _BrowseRequest(this.location, this.cursor);

  final String location;
  final String? cursor;
}
