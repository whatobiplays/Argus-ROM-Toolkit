import 'dart:ui' show CheckedState;

import 'package:argus/core/client/client.dart';
import 'package:argus/core/design_system/argus_theme.dart';
import 'package:argus/features/settings/application/appearance_settings_controller.dart';
import 'package:argus/features/settings/application/appearance_settings_dependencies.dart';
import 'package:argus/features/settings/application/appearance_settings_state.dart';
import 'package:argus/features/settings/settings.dart';
import 'package:flutter/material.dart' hide ThemeMode;
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'appearance_settings_test_fakes.dart';

void main() {
  bool subtreeHasChecked(SemanticsNode node) {
    if (node.getSemanticsData().flagsCollection.isChecked ==
        CheckedState.isTrue) {
      return true;
    }
    var found = false;
    node.visitChildren((child) {
      found = subtreeHasChecked(child) || found;
      return true;
    });
    return found;
  }

  late FakeSettingsApi api;

  setUp(() {
    api = FakeSettingsApi();
  });

  Future<ProviderContainer> pumpPage(
    WidgetTester tester, {
    double width = 720,
    double textScale = 1,
  }) async {
    final container = ProviderContainer(
      overrides: [
        appearanceSettingsApiProvider.overrideWithValue(api),
        appearanceRuntimeContextProvider.overrideWith(
          (ref) => ref.watch(appearanceRuntimeContextHostProvider),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(appearanceRuntimeContextHostProvider.notifier)
        .setContext(
          AppearanceRuntimeContext.ready(
            runtimeInstanceId: appearanceTestId('a'),
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ArgusTheme.light,
          home: SizedBox(
            width: width,
            height: 800,
            child: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 800),
                textScaler: TextScaler.linear(textScale),
              ),
              child: const SettingsPage(),
            ),
          ),
        ),
      ),
    );
    return container;
  }

  Future<void> loadAppearance(WidgetTester tester, ThemeMode mode) async {
    await tester.pump();
    api.readRequests.single.complete(AppearanceSettings(themeMode: mode));
    await tester.pumpAndSettle();
  }

  Finder lightTile() => find.byType(RadioListTile<ThemeMode>).at(1);

  testWidgets('renders the real Phase 000 Appearance section', (tester) async {
    await pumpPage(tester);
    await loadAppearance(tester, ThemeMode.light);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Theme Mode'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(
      find.text('Follows your operating system appearance.'),
      findsOneWidget,
    );
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(
      find.textContaining('Appearance controls will be available'),
      findsNothing,
    );
    expect(find.text('Apply'), findsNothing);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('authoritative selection is presented and selected', (
    tester,
  ) async {
    await pumpPage(tester);
    await loadAppearance(tester, ThemeMode.light);

    final group = tester.widget<RadioGroup<ThemeMode>>(
      find.byType(RadioGroup<ThemeMode>),
    );
    expect(group.groupValue, ThemeMode.light);
  });

  testWidgets('System helper copy is discoverable next to System', (
    tester,
  ) async {
    await pumpPage(tester);
    await loadAppearance(tester, ThemeMode.system);

    final systemTile = find.byType(RadioListTile<ThemeMode>).at(0);
    expect(
      find.descendant(
        of: systemTile,
        matching: find.text('Follows your operating system appearance.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('selection presents optimistically with single-flight status', (
    tester,
  ) async {
    await pumpPage(tester);
    await loadAppearance(tester, ThemeMode.light);

    await tester.tap(find.text('Dark'));
    await tester.pump();

    final group = tester.widget<RadioGroup<ThemeMode>>(
      find.byType(RadioGroup<ThemeMode>),
    );
    expect(group.groupValue, ThemeMode.dark);
    expect(find.text('Saving appearance settings…'), findsOneWidget);

    // A further selection cannot dispatch a second mutation while pending.
    await tester.tap(find.text('System'));
    await tester.pump();
    expect(api.updateRequests, hasLength(1));

    api.updateRequests.single.completer.complete();
    await tester.pump();
    api.readRequests[1].complete(
      const AppearanceSettings(themeMode: ThemeMode.dark),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saving appearance settings…'), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.text('Settings')),
    );
    expect(
      container
          .read(appearanceSettingsControllerProvider)
          .value!
          .confirmed
          .themeMode,
      ThemeMode.dark,
    );
  });

  testWidgets('definite failure rolls back with bounded local copy', (
    tester,
  ) async {
    await pumpPage(tester);
    await loadAppearance(tester, ThemeMode.light);
    final failure = ApplicationFailure(
      ClientApplicationError(
        code: const ErrorCode('ARGUS.V1.APPEARANCE.UPDATE_FAILED'),
        category: ErrorCategory.persistence,
        severity: ApplicationSeverity.error,
        recoverability: Recoverability.userAction,
        retryPolicy: RetryPolicy.userInitiated,
        messageKey: const MessageKey('appearance.update_failed'),
        traceId: TraceId('c' * 32),
        safeContext: const <SafeContextEntry>[],
      ),
    );

    await tester.tap(find.text('Dark'));
    await tester.pump();
    api.updateRequests.single.completer.completeError(failure);
    await tester.pumpAndSettle();

    final group = tester.widget<RadioGroup<ThemeMode>>(
      find.byType(RadioGroup<ThemeMode>),
    );
    expect(group.groupValue, ThemeMode.light);
    expect(
      find.text('Argus could not save the appearance setting.'),
      findsOneWidget,
    );
    expect(find.textContaining('ARGUS.V1'), findsNothing);
    expect(find.textContaining('ApplicationFailure'), findsNothing);

    // Authority remains synchronized, so a new selection is admissible.
    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(api.updateRequests, hasLength(2));
  });

  testWidgets(
    'uncertain synchronization blocks writes and offers read-only retry',
    (tester) async {
      await pumpPage(tester);
      await loadAppearance(tester, ThemeMode.light);

      await tester.tap(find.text('Dark'));
      await tester.pump();
      api.updateRequests.single.completer.complete();
      await tester.pump();
      api.readRequests[1].completeError(
        const TransportFailure(
          'reconciliation read failed',
          kind: TransportFailureKind.communicationFailed,
        ),
      );
      await tester.pumpAndSettle();

      final group = tester.widget<RadioGroup<ThemeMode>>(
        find.byType(RadioGroup<ThemeMode>),
      );
      expect(group.groupValue, ThemeMode.light);
      expect(
        find.text(
          'Argus could not confirm the current appearance setting. The displayed '
          'selection is the last known value.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Dark'));
      await tester.pump();
      expect(api.updateRequests, hasLength(1));

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(api.updateRequests, hasLength(1));
      expect(api.readRequests, hasLength(3));

      api.readRequests[2].complete(
        const AppearanceSettings(themeMode: ThemeMode.dark),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Argus could not confirm the current appearance setting. The displayed '
          'selection is the last known value.',
        ),
        findsNothing,
      );
      await tester.tap(find.text('System'));
      await tester.pump();
      expect(api.updateRequests, hasLength(2));
    },
  );

  testWidgets('theme mode choices are keyboard operable', (tester) async {
    await pumpPage(tester);
    await loadAppearance(tester, ThemeMode.light);

    // Tab focuses the selected Light radio, then ArrowDown selects Dark.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(api.updateRequests, hasLength(1));
    expect(api.updateRequests.single.settings.themeMode, ThemeMode.dark);
  });

  testWidgets('selected state is exposed through semantics', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpPage(tester);
    await loadAppearance(tester, ThemeMode.light);

    expect(subtreeHasChecked(tester.getSemantics(lightTile())), isTrue);
    expect(
      subtreeHasChecked(
        tester.getSemantics(find.byType(RadioListTile<ThemeMode>).at(2)),
      ),
      isFalse,
    );
    handle.dispose();
  });

  testWidgets('theme mode targets meet practical Material sizes', (
    tester,
  ) async {
    await pumpPage(tester);
    await loadAppearance(tester, ThemeMode.light);

    for (final tile in find.byType(RadioListTile<ThemeMode>).evaluate()) {
      expect(
        tester.getSize(find.byWidget(tile.widget)).height,
        greaterThanOrEqualTo(48),
      );
    }
  });

  for (final testCase in <({double width, double textScale})>[
    (width: 480, textScale: 1),
    (width: 480, textScale: 2),
    (width: 1440, textScale: 1),
    (width: 1440, textScale: 2),
  ]) {
    testWidgets(
      'renders at ${testCase.width} logical pixels and ${testCase.textScale}x text scale',
      (tester) async {
        await pumpPage(
          tester,
          width: testCase.width,
          textScale: testCase.textScale,
        );
        await loadAppearance(tester, ThemeMode.light);

        expect(find.text('Settings'), findsOneWidget);
        expect(find.byType(RadioListTile<ThemeMode>), findsNWidgets(3));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
