import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sources = _authoredProductionSources();

  test('main remains a thin bootstrap entry point', () {
    final main = sources['main.dart']!;

    expect(main, contains('bootstrapArgus'));
    for (final forbidden in <String>[
      'ProviderScope',
      'MaterialApp',
      'GoRouter',
      'package:argus/features/',
    ]) {
      expect(main, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('the root ProviderScope has one explicit owner', () {
    final owners = sources.entries
        .where((entry) => entry.value.contains('ProviderScope('))
        .map((entry) => entry.key)
        .toList(growable: false);

    expect(owners, <String>['app/bootstrap/app_bootstrap.dart']);
  });

  test('generated provider declarations have adjacent generated sources', () {
    final generatedProviderFiles = sources.entries
        .where((entry) => RegExp(r'@Riverpod|@riverpod').hasMatch(entry.value))
        .map((entry) => entry.key)
        .toList(growable: false);

    expect(generatedProviderFiles, <String>['app/routing/app_router.dart']);
    for (final relativePath in generatedProviderFiles) {
      final source = sources[relativePath]!;
      final basename = relativePath.split('/').last.replaceFirst('.dart', '');
      expect(source, contains("part '$basename.g.dart';"));
      expect(
        File(
          '${Directory.current.path}/lib/${relativePath.replaceFirst('.dart', '.g.dart')}',
        ).existsSync(),
        isTrue,
        reason: relativePath,
      );
    }
  });

  test('core responsive code remains independent of app and services', () {
    _expectNoForbiddenImports(
      sources,
      prefix: 'core/responsive/',
      forbidden: <String>[
        'app/',
        'features/',
        'riverpod',
        'go_router',
        'flutter_rust_bridge',
        'sqlite',
        'client',
      ],
    );
  });

  test('core design-system code remains independent of app and services', () {
    _expectNoForbiddenImports(
      sources,
      prefix: 'core/design_system/',
      forbidden: <String>[
        'app/',
        'features/',
        'flutter_rust_bridge',
        'riverpod',
        'repository',
        'sqlite',
        'client',
      ],
    );
  });

  test('features do not own routing or router state', () {
    _expectNoForbiddenImports(
      sources,
      prefix: 'features/',
      forbidden: <String>['app/routing', 'go_router', 'GoRouter('],
    );
  });

  test('production route construction remains sparse and centralized', () {
    for (final entry in sources.entries) {
      if (entry.key != 'app/routing/app_routes.dart') {
        expect(entry.value, isNot(contains("'/settings'")), reason: entry.key);
        expect(entry.value, isNot(contains('"/settings"')), reason: entry.key);
      }
      expect(entry.value, isNot(contains("'/more'")), reason: entry.key);
      expect(entry.value, isNot(contains('"/more"')), reason: entry.key);
    }
  });

  test(
    'production source excludes future integrations and alternate shells',
    () {
      const forbiddenConcepts = <String>[
        'StatefulShellRoute',
        'flutter_rust_bridge',
        'frb_generated',
        'ArgusClient',
        'SQLite',
        'sqlite',
        'isDesktop',
        'isTablet',
        'isPhone',
        'LibraryRoute',
        'CollectionsRoute',
        'JobsRoute',
        'SourcesRoute',
        'GameDetailRoute',
        'DiagnosticsRoute',
      ];

      for (final entry in sources.entries) {
        for (final forbidden in forbiddenConcepts) {
          expect(entry.value, isNot(contains(forbidden)), reason: entry.key);
        }
      }
      expect(
        sources.keys.where((path) => path.startsWith('features/')).toList(),
        <String>[
          'features/settings/settings.dart',
          'features/settings/src/settings_page.dart',
        ],
      );
    },
  );

  test('breakpoint literals have one source of truth', () {
    final breakpointPattern = RegExp(r'(?<!\d)(600|840|1200)(?!\d)');
    for (final entry in sources.entries) {
      if (entry.key != 'core/responsive/window_size_class.dart') {
        expect(
          breakpointPattern.hasMatch(entry.value),
          isFalse,
          reason: entry.key,
        );
      }
    }
  });

  test('Material 3 theme construction has one owner', () {
    final themeConstructors = sources.entries
        .where((entry) => entry.value.contains('ThemeData('))
        .map((entry) => entry.key)
        .toList(growable: false);

    expect(themeConstructors, <String>['core/design_system/argus_theme.dart']);
  });

  test('Settings public barrel owns the feature-private export boundary', () {
    expect(
      sources['features/settings/settings.dart'],
      "export 'src/settings_page.dart' show SettingsPage;\n",
    );
    for (final entry in sources.entries) {
      if (entry.key != 'features/settings/settings.dart') {
        expect(
          entry.value,
          isNot(contains('features/settings/src/')),
          reason: entry.key,
        );
      }
    }
  });
}

Map<String, String> _authoredProductionSources() {
  final libDirectory = Directory('${Directory.current.path}/lib');
  final files =
      libDirectory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) => !file.path.endsWith('.g.dart'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));

  return <String, String>{
    for (final file in files)
      _relativeToLib(file.path, libDirectory.path): file.readAsStringSync(),
  };
}

String _relativeToLib(String filePath, String libPath) {
  return filePath
      .substring(libPath.length + 1)
      .replaceAll(Platform.pathSeparator, '/');
}

void _expectNoForbiddenImports(
  Map<String, String> sources, {
  required String prefix,
  required List<String> forbidden,
}) {
  for (final entry in sources.entries.where(
    (entry) => entry.key.startsWith(prefix),
  )) {
    for (final concept in forbidden) {
      expect(entry.value, isNot(contains(concept)), reason: entry.key);
    }
  }
}
