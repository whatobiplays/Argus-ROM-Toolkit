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

    expect(generatedProviderFiles, <String>[
      'app/bootstrap/appearance_event_coordinator.dart',
      'app/bootstrap/application_presentation.dart',
      'app/bootstrap/client_bootstrap.dart',
      'app/bootstrap/jobs_event_coordinator.dart',
      'app/bootstrap/sources_event_coordinator.dart',
      'app/routing/app_router.dart',
      'features/jobs/application/active_job_summary_controller.dart',
      'features/jobs/application/job_detail_controller.dart',
      'features/jobs/application/jobs_list_controller.dart',
      'features/jobs/jobs_composition.dart',
      'features/settings/application/appearance_settings_controller.dart',
      'features/settings/application/appearance_settings_dependencies.dart',
      'features/sources/application/add_library_folder_controller.dart',
      'features/sources/application/root_detail_controller.dart',
      'features/sources/application/root_list_controller.dart',
      'features/sources/application/sources_session_presentation.dart',
      'features/sources/presentation/library_folder_picker.dart',
      'features/sources/sources_composition.dart',
      'features/startup/application/app_readiness.dart',
      'features/startup/application/startup_controller.dart',
      'features/startup/presentation/presentation_seams.dart',
    ]);
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
      if (entry.key != 'app/routing/app_routes.dart' &&
          entry.key != 'app/shell/application_shell.dart') {
        expect(entry.value, isNot(contains("'/settings'")), reason: entry.key);
        expect(entry.value, isNot(contains('"/settings"')), reason: entry.key);
      }
      expect(entry.value, isNot(contains("'/more'")), reason: entry.key);
      expect(entry.value, isNot(contains('"/more"')), reason: entry.key);
      expect(entry.value, isNot(contains("'/startup'")), reason: entry.key);
      expect(entry.value, isNot(contains('"/startup"')), reason: entry.key);
    }
  });

  test(
    'production source excludes future integrations and alternate shells',
    () {
      const forbiddenConcepts = <String>[
        'StatefulShellRoute',
        'SQLite',
        'sqlite',
        'isDesktop',
        'isTablet',
        'isPhone',
        'LibraryRoute',
        'CollectionsRoute',
        'GameDetailRoute',
        'DiagnosticsRoute',
      ];

      for (final entry in sources.entries) {
        for (final forbidden in forbiddenConcepts) {
          expect(entry.value, isNot(contains(forbidden)), reason: entry.key);
        }
      }
      for (final entry in sources.entries.where(
        (entry) =>
            !entry.key.startsWith('core/bridge/') &&
            !entry.key.startsWith('core/client/') &&
            entry.key != 'app/bootstrap/client_bootstrap.dart',
      )) {
        expect(
          entry.value,
          isNot(contains('flutter_rust_bridge')),
          reason: entry.key,
        );
        expect(
          entry.value,
          isNot(contains('frb_generated')),
          reason: entry.key,
        );
        if (entry.key == 'app/bootstrap/app_bootstrap.dart') {
          // Slice 009's approved narrow bootstrap seam names the gateway
          // factory interface; every other concrete-client token stays
          // forbidden so only that seam may mention the client layer.
          expect(
            entry.value.replaceAll('ArgusClientGateway', ''),
            isNot(contains('ArgusClient')),
            reason: entry.key,
          );
        } else {
          expect(
            entry.value,
            isNot(contains('ArgusClient')),
            reason: entry.key,
          );
        }
      }
      expect(
        sources.keys.where((path) => path.startsWith('features/')).toList(),
        <String>[
          'features/jobs/application/active_job_summary_controller.dart',
          'features/jobs/application/job_detail_controller.dart',
          'features/jobs/application/jobs_list_controller.dart',
          'features/jobs/application/jobs_state.dart',
          'features/jobs/jobs.dart',
          'features/jobs/jobs_composition.dart',
          'features/jobs/presentation/job_detail_page.dart',
          'features/jobs/presentation/jobs_messages.dart',
          'features/jobs/presentation/jobs_page.dart',
          'features/settings/application/appearance_settings_controller.dart',
          'features/settings/application/appearance_settings_dependencies.dart',
          'features/settings/application/appearance_settings_state.dart',
          'features/settings/presentation/appearance_initialization_view.dart',
          'features/settings/presentation/appearance_messages.dart',
          'features/settings/presentation/settings_page.dart',
          'features/settings/presentation/theme_mode_control.dart',
          'features/settings/settings.dart',
          'features/settings/settings_composition.dart',
          'features/sources/application/add_library_folder_controller.dart',
          'features/sources/application/root_detail_controller.dart',
          'features/sources/application/root_list_controller.dart',
          'features/sources/application/sources_session_presentation.dart',
          'features/sources/application/sources_state.dart',
          'features/sources/presentation/add_library_folder_flow.dart',
          'features/sources/presentation/library_folder_picker.dart',
          'features/sources/presentation/remove_root_dialog.dart',
          'features/sources/presentation/root_detail_page.dart',
          'features/sources/presentation/root_sidebar.dart',
          'features/sources/presentation/sources_messages.dart',
          'features/sources/presentation/sources_page.dart',
          'features/sources/sources.dart',
          'features/sources/sources_composition.dart',
          'features/startup/application/app_readiness.dart',
          'features/startup/application/startup_controller.dart',
          'features/startup/application/startup_state.dart',
          'features/startup/presentation/bootstrap_failure_view.dart',
          'features/startup/presentation/presentation_seams.dart',
          'features/startup/presentation/runtime_unavailable_view.dart',
          'features/startup/presentation/shutdown_views.dart',
          'features/startup/presentation/startup_failure_view.dart',
          'features/startup/presentation/startup_gate.dart',
          'features/startup/presentation/startup_loading_view.dart',
          'features/startup/presentation/startup_messages.dart',
          'features/startup/startup.dart',
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
      "export 'presentation/settings_page.dart' show SettingsPage;\n",
    );
    for (final entry in sources.entries) {
      if (entry.key.startsWith('features/settings/')) continue;
      expect(
        entry.value,
        isNot(contains('features/settings/application/')),
        reason: entry.key,
      );
      expect(
        entry.value,
        isNot(contains('features/settings/presentation/')),
        reason: entry.key,
      );
      expect(
        entry.value,
        isNot(contains('features/settings/src/')),
        reason: entry.key,
      );
    }
  });

  test('settings application stays framework-, bridge-, and routing-free', () {
    _expectNoForbiddenImports(
      sources,
      prefix: 'features/settings/application/',
      forbidden: <String>[
        'app/',
        'features/startup/',
        'features/',
        'core/bridge/',
        'frb_generated',
        'core/client/src/',
        'flutter_rust_bridge',
        'sqlite',
        'BuildContext',
        'go_router',
        'dart:io',
        'file_selector',
      ],
    );
  });

  test('sources feature stays framework-, bridge-, and routing-free', () {
    final sourcesApplication = sources.entries
        .where((entry) => entry.key.startsWith('features/sources/application/'))
        .toList();
    expect(sourcesApplication, isNotEmpty);

    for (final entry in sourcesApplication) {
      for (final forbidden in <String>[
        'package:flutter/',
        'dart:io',
        'file_selector',
        'core/bridge/',
        'flutter_rust_bridge',
        'app/routing',
        'go_router',
        'GoRouter(',
      ]) {
        expect(
          entry.value,
          isNot(contains(forbidden)),
          reason: '${entry.key} must stay focused',
        );
      }
    }

    // Sources feature code never reaches the root client implementation
    // directly; it consumes focused APIs through composition.
    for (final entry in sources.entries.where(
      (entry) => entry.key.startsWith('features/sources/'),
    )) {
      expect(
        entry.value,
        isNot(contains('core/client/src/')),
        reason: entry.key,
      );
      expect(entry.value, isNot(contains('core/bridge/')), reason: entry.key);
    }
  });

  test('settings presentation has no generated or direct API calls', () {
    for (final entry in sources.entries) {
      if (!entry.key.startsWith('features/settings/presentation/')) continue;
      expect(entry.value, isNot(contains('.g.dart')), reason: entry.key);
      expect(entry.value, isNot(contains('.freezed.dart')), reason: entry.key);
      expect(
        entry.value,
        isNot(contains('flutter_rust_bridge')),
        reason: entry.key,
      );
      expect(
        entry.value,
        isNot(contains('getAppearanceSettings(')),
        reason: entry.key,
      );
      expect(
        entry.value,
        isNot(contains('updateAppearanceSettings(')),
        reason: entry.key,
      );
    }
  });

  test('settings presentation never subscribes to APIs or event channels', () {
    const forbiddenConcepts = <String>[
      '.listen(',
      'StreamSubscription',
      'EventsApi',
      'runtimeEvents',
      'appearanceReconciliationDemand',
      'appearanceEventCoordinator',
    ];
    for (final entry in sources.entries) {
      if (!entry.key.startsWith('features/settings/presentation/')) continue;
      for (final concept in forbiddenConcepts) {
        expect(entry.value, isNot(contains(concept)), reason: entry.key);
      }
    }
  });

  test('router policy never executes settings workflows', () {
    const settingsConcepts = <String>[
      'SettingsApi',
      'getAppearanceSettings',
      'updateAppearanceSettings',
      'AppearanceSettingsController',
      'appearanceSettingsControllerProvider',
      'AppearanceReconciliationDemand',
      'appearanceReconciliationDemandProvider',
      'AppearanceEventCoordinator',
      'appearanceEventCoordinatorProvider',
      'ApplicationPresentationGate',
      'selectThemeMode',
      'retryAuthoritativeRead',
    ];
    for (final entry in sources.entries) {
      if (!entry.key.startsWith('app/routing/')) continue;
      for (final concept in settingsConcepts) {
        expect(entry.value, isNot(contains(concept)), reason: entry.key);
      }
    }
  });

  test('root theme mode has one derived assignment and no mutable owner', () {
    final argusApp = sources['app/bootstrap/argus_app.dart']!;
    expect(argusApp, contains('rootThemeModeProvider'));
    expect(argusApp, contains('themeMode:'));
    expect(argusApp, isNot(contains('themeMode: ThemeMode.system')));
    for (final entry in sources.entries) {
      if (entry.key == 'app/bootstrap/argus_app.dart' ||
          entry.key == 'app/bootstrap/application_presentation.dart') {
        continue;
      }
      expect(entry.value, isNot(contains('MaterialApp(')), reason: entry.key);
      expect(entry.value, isNot(contains('rootThemeMode')), reason: entry.key);
    }
  });

  test('appearance state uses typed ThemeMode, not wire strings', () {
    for (final entry in sources.entries) {
      if (!entry.key.startsWith('features/settings/')) continue;
      expect(entry.value, isNot(contains("'system'")), reason: entry.key);
      expect(entry.value, isNot(contains("'light'")), reason: entry.key);
      expect(entry.value, isNot(contains("'dark'")), reason: entry.key);
    }
  });

  test('only app-level event coordination interprets envelope continuity for '
      'appearance', () {
    const coordinator = 'app/bootstrap/appearance_event_coordinator.dart';
    const appAppearanceSources = <String>[
      'app/bootstrap/app_bootstrap.dart',
      'app/bootstrap/application_presentation.dart',
      'app/bootstrap/application_presentation_gate.dart',
      'app/bootstrap/argus_app.dart',
    ];
    const forbiddenConcepts = <String>[
      'EventsApi',
      'RuntimeEvent',
      'RuntimeEventPayload',
      'sequence',
      'gap',
      'reconnect',
      'runtimeEventsProvider',
      'subscribeEvents',
    ];
    for (final entry in sources.entries) {
      final isCoordinator = entry.key == coordinator;
      final isBounded =
          entry.key.startsWith('features/settings/') ||
          appAppearanceSources.contains(entry.key);
      if (!isBounded || isCoordinator) continue;
      for (final concept in forbiddenConcepts) {
        expect(entry.value, isNot(contains(concept)), reason: entry.key);
      }
    }

    final coordinatorSource = sources[coordinator]!;
    expect(coordinatorSource, contains('runtimeEventsProvider'));
    expect(coordinatorSource, contains('readyRuntimeInstanceIdProvider'));
    expect(coordinatorSource, contains('AppearanceReconciliationDemandSource'));
    expect(
      coordinatorSource,
      contains('AppearanceReconciliationDemandRefresh'),
    );
  });

  test('appearance production sources own no process orchestration or restart '
      'harness', () {
    // Slice 009 proves restart restoration through integration tests, so
    // appearance sources may describe restart behavior in prose. They must
    // not launch child processes, inspect the Slice 009 test environment,
    // or add a second persistence mechanism: process orchestration and
    // harness input stay test-owned.
    const forbiddenConcepts = <String>[
      'dart:io',
      'Process.run',
      'ARGUS_PHASE_000_RESTART_MODE',
      'ARGUS_PHASE_000_DATA_DIR',
    ];
    for (final entry in sources.entries) {
      final isAppAppearanceSource =
          entry.key == 'app/bootstrap/application_presentation.dart' ||
          entry.key == 'app/bootstrap/application_presentation_gate.dart' ||
          entry.key == 'app/bootstrap/app_bootstrap.dart' ||
          entry.key == 'app/bootstrap/argus_app.dart';
      if (!entry.key.startsWith('features/settings/') &&
          !isAppAppearanceSource) {
        continue;
      }
      for (final concept in forbiddenConcepts) {
        expect(entry.value, isNot(contains(concept)), reason: entry.key);
      }
    }
  });

  test('features never import bridge or client implementation layers', () {
    _expectNoForbiddenImports(
      sources,
      prefix: 'features/',
      forbidden: <String>[
        'core/bridge/',
        'frb_generated',
        'core/client/src/',
        'flutter_rust_bridge',
      ],
    );
  });

  test('startup application stays framework-, bridge-, and routing-free', () {
    _expectNoForbiddenImports(
      sources,
      prefix: 'features/startup/application/',
      forbidden: <String>[
        'package:flutter/',
        'go_router',
        'core/bridge/',
        'frb_generated',
        'core/client/src/',
        'dart:io',
        'file_selector',
        'BuildContext',
        'app/routing',
      ],
    );
  });

  test('router policy never executes startup or recovery APIs', () {
    const recoveryConcepts = <String>[
      'retryStartup',
      'resetAppearanceSettings',
      'exitFailedRuntime',
      'reconcileRuntime',
      'loadTechnicalDetails',
      'openStartupDataDirectory',
      'exportStartupDiagnostics',
      'clientBootstrap',
      'StartupController',
      'StartupGate',
      'features/startup',
    ];
    for (final entry in sources.entries) {
      if (!entry.key.startsWith('app/routing/')) continue;
      for (final concept in recoveryConcepts) {
        expect(entry.value, isNot(contains(concept)), reason: entry.key);
      }
    }
  });

  test('startup keeps one public barrel and no native subscriptions', () {
    final barrel = sources['features/startup/startup.dart'];
    expect(barrel, isNotNull);
    expect(barrel, isNot(contains("import '")));
    expect(barrel, contains("export 'application/"));
    expect(barrel, contains("export 'presentation/"));
    for (final entry in sources.entries) {
      if (!entry.key.startsWith('features/startup/')) continue;
      expect(
        entry.value,
        isNot(contains('subscribeEvents')),
        reason: entry.key,
      );
      expect(
        entry.value,
        isNot(contains('error.toString()')),
        reason: entry.key,
      );
    }
  });

  test('core client remains pure Dart and bridge-independent', () {
    _expectNoForbiddenImports(
      sources,
      prefix: 'core/client/',
      forbidden: <String>[
        "package:flutter/",
        'flutter_riverpod',
        'flutter_rust_bridge',
        'core/bridge/',
        'features/',
        'go_router',
      ],
    );
    final barrel = sources['core/client/client.dart']!;
    expect(barrel, isNot(contains('bridge')));
    expect(barrel, isNot(contains('frb_generated')));
  });

  test('focused API signatures use Argus-owned types only', () {
    final ports = sources['core/client/src/ports.dart']!;
    for (final line in ports.split('\n')) {
      if (line.contains('Future<') || line.contains('Stream<')) {
        expect(line, isNot(contains('dto.')), reason: line);
        expect(line, isNot(contains('frb.')), reason: line);
        expect(line, isNot(contains('RustStreamSink')), reason: line);
      }
    }
  });

  test('generated FRB source is contained under core/bridge/generated', () {
    final libDirectory = Directory('${Directory.current.path}/lib');
    for (final file
        in libDirectory
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final content = file.readAsStringSync();
      if (content.contains('kDefaultExternalLibraryLoaderConfig') ||
          content.contains('class RustLib')) {
        expect(
          file.path.replaceAll('\\', '/'),
          contains('/core/bridge/generated/'),
          reason: file.path,
        );
      }
    }
  });

  test('no capability bag or speculative future API family exists', () {
    const forbiddenConcepts = <String>[
      'RuntimeCapabilitiesDto',
      'LibraryApi',
      'CollectionsApi',
      'GameApi',
      'ProviderApi',
      'Invoke(',
      'ExecuteCommand(',
      'ExecuteQuery(',
    ];
    for (final entry in sources.entries) {
      for (final concept in forbiddenConcepts) {
        expect(entry.value, isNot(contains(concept)), reason: entry.key);
      }
    }
  });

  test('Rust public contracts stay technology-neutral', () {
    for (final path in <String>[
      '../rust/crates/argus-application/src/lib.rs',
      '../rust/crates/argus-runtime/src/lib.rs',
    ]) {
      final content = File(
        '${Directory.current.path}/$path',
      ).readAsStringSync();
      for (final line in content.split('\n')) {
        if (line.contains('pub use') ||
            line.contains('pub struct') ||
            line.contains('pub enum')) {
          expect(
            line,
            isNot(contains('flutter_rust_bridge')),
            reason: '$path:$line',
          );
          expect(line, isNot(contains('Sqlite')), reason: '$path:$line');
          expect(line, isNot(contains('rusqlite')), reason: '$path:$line');
          expect(line, isNot(contains('ZipWriter')), reason: '$path:$line');
        }
      }
    }
  });

  test('runtime event notifications never carry full runtime snapshots', () {
    final models = sources['core/client/src/models.dart']!;
    final eventSection = models.substring(
      models.indexOf('sealed class RuntimeEventPayload'),
    );
    expect(eventSection, isNot(contains('RuntimeState state')));
    expect(eventSection, isNot(contains('required RuntimeState')));

    final generated = File(
      '${Directory.current.path}/lib/core/bridge/generated/lib.dart',
    ).readAsStringSync();
    expect(generated, isNot(contains('state: RuntimeStateDto')));
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
          .where((file) => !file.path.endsWith('.freezed.dart'))
          .where((file) => !file.path.contains('/core/bridge/generated/'))
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
