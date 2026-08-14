import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:argus/features/startup/presentation/bootstrap_failure_view.dart';
import 'package:argus/features/startup/presentation/runtime_unavailable_view.dart';
import 'package:argus/features/startup/presentation/startup_failure_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'startup_test_fakes.dart';

void main() {
  Future<ProviderContainer> pumpView(
    WidgetTester tester, {
    required Widget view,
    required FakeClientBootstrap bootstrap,
    FakeRuntimeApi? runtime,
    FakeDiagnosticsApi? diagnostics,
    FakeEventsApi? events,
    AppTerminator? terminator,
    DiagnosticsDestinationPicker? picker,
  }) async {
    final container = ProviderContainer(
      overrides: [
        clientBootstrapProvider.overrideWithValue(bootstrap),
        runtimeApiProvider.overrideWithValue(runtime ?? FakeRuntimeApi()),
        diagnosticsApiProvider.overrideWithValue(
          diagnostics ?? FakeDiagnosticsApi(),
        ),
        runtimeEventsProvider.overrideWithValue(events ?? FakeEventsApi()),
        if (terminator != null)
          appTerminatorProvider.overrideWithValue(terminator),
        if (picker != null)
          diagnosticsDestinationPickerProvider.overrideWithValue(picker),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: view),
      ),
    );
    container.read(startupControllerProvider);
    await tester.pump();
    return container;
  }

  Future<void> seedFailed(
    WidgetTester tester,
    ProviderContainer container,
    FakeClientBootstrap bootstrap, {
    List<RecoveryActionKind> actions = const <RecoveryActionKind>[],
  }) async {
    container.read(startupControllerProvider);
    for (var i = 0; i < 10 && bootstrap.completers.isEmpty; i++) {
      await tester.pump();
    }
    bootstrap.completers.first.complete(
      failedRuntime(
        id: 'a',
        actions: actions.isEmpty
            ? const <RecoveryActionKind>[
                RecoveryActionKind.resetAppearanceSettings,
                RecoveryActionKind.retryStartup,
                RecoveryActionKind.exportDiagnostics,
                RecoveryActionKind.copyTechnicalDetails,
                RecoveryActionKind.openDataDirectory,
                RecoveryActionKind.exit,
              ]
            : actions,
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('bootstrap failure view retries and exits', (tester) async {
    final bootstrap = FakeClientBootstrap();
    var terminated = 0;
    await pumpView(
      tester,
      view: const BootstrapFailureView(
        failure: TransportFailure('native unavailable'),
      ),
      bootstrap: bootstrap,
      terminator: () => terminated++,
    );
    bootstrap.completers.first.completeError(
      const TransportFailure('native unavailable'),
      StackTrace.current,
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Argus could not initialize'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('retry-initialization-button')),
    );
    await tester.pump();
    expect(bootstrap.initializeCalls, 2);

    await tester.tap(
      find.byKey(const ValueKey<String>('bootstrap-exit-button')),
    );
    await tester.pump();
    expect(terminated, 1);
  });

  testWidgets('bootstrap failure receives one-time focus', (tester) async {
    final bootstrap = FakeClientBootstrap();
    await pumpView(
      tester,
      view: const BootstrapFailureView(
        failure: TransportFailure('native unavailable'),
      ),
      bootstrap: bootstrap,
    );
    bootstrap.completers.first.completeError(
      const TransportFailure('native unavailable'),
      StackTrace.current,
    );
    await tester.pump();
    await tester.pump();

    final retry = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('retry-initialization-button')),
    );
    expect(retry.focusNode?.hasFocus, isTrue);

    await tester.pump();
    expect(retry.focusNode?.hasFocus, isTrue);
  });

  testWidgets('recovery view renders all advertised actions in order', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final container = await pumpView(
      tester,
      view: StartupFailureView(state: failedStartupState(id: 'a')),
      bootstrap: bootstrap,
    );
    await seedFailed(tester, container, bootstrap);

    expect(
      find.byKey(const ValueKey<String>('reset-appearance-settings-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('retry-startup-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('export-diagnostics-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('copy-technical-details-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('technical-details-disclosure')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('open-data-directory-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('exit-application-button')),
      findsOneWidget,
    );

    final reset = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('reset-appearance-settings-button')),
    );
    expect(reset.focusNode?.hasFocus, isTrue);
  });

  testWidgets('actions absent from the failure are not rendered', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final container = await pumpView(
      tester,
      view: StartupFailureView(
        state: failedStartupState(
          id: 'a',
          actions: const <RecoveryActionKind>[RecoveryActionKind.exit],
        ),
      ),
      bootstrap: bootstrap,
    );
    await seedFailed(
      tester,
      container,
      bootstrap,
      actions: const <RecoveryActionKind>[RecoveryActionKind.exit],
    );

    expect(
      find.byKey(const ValueKey<String>('reset-appearance-settings-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('retry-startup-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('export-diagnostics-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('copy-technical-details-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('open-data-directory-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('exit-application-button')),
      findsOneWidget,
    );
  });

  testWidgets('reset confirmation cancel makes zero reset calls', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final runtime = FakeRuntimeApi();
    final container = await pumpView(
      tester,
      view: StartupFailureView(state: failedStartupState(id: 'a')),
      bootstrap: bootstrap,
      runtime: runtime,
    );
    await seedFailed(tester, container, bootstrap);

    await tester.tap(
      find.byKey(const ValueKey<String>('reset-appearance-settings-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reset appearance settings?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('reset-cancel-button')));
    await tester.pumpAndSettle();
    expect(runtime.resetRequests, isEmpty);
  });

  testWidgets('reset confirmation confirm dispatches exactly once', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final runtime = FakeRuntimeApi();
    final container = await pumpView(
      tester,
      view: StartupFailureView(state: failedStartupState(id: 'a')),
      bootstrap: bootstrap,
      runtime: runtime,
    );
    await seedFailed(tester, container, bootstrap);

    await tester.tap(
      find.byKey(const ValueKey<String>('reset-appearance-settings-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('reset-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect(runtime.resetRequests, hasLength(1));
    expect(runtime.resetRequests.single.runtimeInstanceId, testId('a'));
  });

  testWidgets('retry running disables runtime actions and shows progress', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final container = await pumpView(
      tester,
      view: StartupFailureView(
        state: failedStartupState(
          id: 'a',
        ).copyWith(recoveryOperation: const RecoveryOperationState.running()),
      ),
      bootstrap: bootstrap,
    );
    await seedFailed(tester, container, bootstrap);

    final retry = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('retry-startup-button')),
    );
    expect(retry.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('runtime-changing recovery disables all diagnostics actions', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final container = await pumpView(
      tester,
      view: StartupFailureView(
        state: failedStartupState(
          id: 'a',
        ).copyWith(recoveryOperation: const RecoveryOperationState.running()),
      ),
      bootstrap: bootstrap,
    );
    await seedFailed(tester, container, bootstrap);

    final export = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey<String>('export-diagnostics-button')),
    );
    expect(export.onPressed, isNull);
    final copy = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey<String>('copy-technical-details-button')),
    );
    expect(copy.onPressed, isNull);
    final open = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey<String>('open-data-directory-button')),
    );
    expect(open.onPressed, isNull);
  });

  testWidgets('export uses the approved destination', (tester) async {
    final bootstrap = FakeClientBootstrap();
    final diagnostics = FakeDiagnosticsApi();
    final container = await pumpView(
      tester,
      view: StartupFailureView(state: failedStartupState(id: 'a')),
      bootstrap: bootstrap,
      diagnostics: diagnostics,
      picker: ({required String suggestedName}) async => '/tmp/chosen.zip',
    );
    await seedFailed(tester, container, bootstrap);

    await tester.tap(
      find.byKey(const ValueKey<String>('export-diagnostics-button')),
    );
    await tester.pumpAndSettle();

    expect(diagnostics.exportRequests, hasLength(1));
    expect(diagnostics.exportDestinations.single, '/tmp/chosen.zip');
  });

  testWidgets('export chooser cancellation makes no controller call', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final diagnostics = FakeDiagnosticsApi();
    final container = await pumpView(
      tester,
      view: StartupFailureView(state: failedStartupState(id: 'a')),
      bootstrap: bootstrap,
      diagnostics: diagnostics,
      picker: ({required String suggestedName}) async => null,
    );
    await seedFailed(tester, container, bootstrap);

    await tester.tap(
      find.byKey(const ValueKey<String>('export-diagnostics-button')),
    );
    await tester.pumpAndSettle();
    expect(diagnostics.exportRequests, isEmpty);
  });

  testWidgets('technical details load lazily, render selectable, and copy', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final bootstrap = FakeClientBootstrap();
    final diagnostics = FakeDiagnosticsApi();
    final container = await pumpView(
      tester,
      view: StartupFailureView(state: failedStartupState(id: 'a')),
      bootstrap: bootstrap,
      diagnostics: diagnostics,
    );
    await seedFailed(tester, container, bootstrap);

    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(diagnostics.detailsRequests, hasLength(1));

    diagnostics.detailsRequests.single.completer.complete(
      RuntimeState.ready(runtimeInstanceId: testId('a')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('copy-technical-details-button')),
    );
    await tester.pumpAndSettle();
    expect(copied, <String>['safe details']);
    expect(find.text('Copied technical details'), findsOneWidget);
  });

  testWidgets('loaded technical details render as selectable text', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final container = await pumpView(
      tester,
      view: StartupFailureView(
        state: failedStartupState(id: 'a').copyWith(
          technicalDetails: const TechnicalDetailsOperationState.loaded(
            TechnicalDetails(text: 'safe copy text'),
          ),
        ),
      ),
      bootstrap: bootstrap,
    );
    await seedFailed(tester, container, bootstrap);

    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('technical-details-text')),
      findsOneWidget,
    );
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('open data directory and exit invoke the controller', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final diagnostics = FakeDiagnosticsApi();
    final runtime = FakeRuntimeApi();
    final container = await pumpView(
      tester,
      view: StartupFailureView(state: failedStartupState(id: 'a')),
      bootstrap: bootstrap,
      diagnostics: diagnostics,
      runtime: runtime,
    );
    await seedFailed(tester, container, bootstrap);

    await tester.tap(
      find.byKey(const ValueKey<String>('open-data-directory-button')),
    );
    await tester.pump();
    expect(diagnostics.openRequests, hasLength(1));

    await tester.tap(
      find.byKey(const ValueKey<String>('exit-application-button')),
    );
    await tester.pump();
    expect(runtime.exitRequests, hasLength(1));
    expect(runtime.exitRequests.single.runtimeInstanceId, testId('a'));
  });

  testWidgets('operation failures render safe messages without raw text', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final container = await pumpView(
      tester,
      view: StartupFailureView(
        state: failedStartupState(id: 'a').copyWith(
          recoveryOperation: RecoveryOperationState.failed(
            applicationFailure(
              messageKey: 'errors.persistence.database_locked',
            ),
          ),
          exportOperation: ExportOperationState.failed(
            const TransportFailure('transport'),
          ),
        ),
      ),
      bootstrap: bootstrap,
    );
    await seedFailed(tester, container, bootstrap);

    expect(
      find.text('The Argus database is locked by another process.'),
      findsOneWidget,
    );
    expect(
      find.text('The operation could not reach the Argus runtime.'),
      findsOneWidget,
    );
    expect(find.textContaining('transport'), findsNothing);
  });

  testWidgets('runtime unavailable renders last-known as non-current', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final runtime = FakeRuntimeApi()
      ..getRuntimeStateError = const TransportFailure('still unreachable');
    final container = await pumpView(
      tester,
      view: RuntimeUnavailableView(state: unavailableState(lastKnownId: 'a')),
      bootstrap: bootstrap,
      runtime: runtime,
    );
    await seedFailed(tester, container, bootstrap);
    final controller = container.read(startupControllerProvider.notifier);
    final retry = controller.retryStartup();
    runtime.retryRequests.single.completer.completeError(
      const TransportFailure('ambiguous transport outcome'),
      StackTrace.current,
    );
    await retry;
    await tester.pump();
    await tester.pump();

    expect(find.text('Connection to Argus was lost'), findsOneWidget);
    expect(
      find.textContaining('Last known status: startup failed.'),
      findsOneWidget,
    );
    expect(find.textContaining('not current'), findsOneWidget);
  });

  testWidgets('runtime unavailable running and failure states are explicit', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final container = await pumpView(
      tester,
      view: RuntimeUnavailableView(
        state: unavailableState(
          lastKnownId: 'a',
          reconciliation: const ReconciliationOperationState.running(),
        ),
      ),
      bootstrap: bootstrap,
    );
    await seedFailed(tester, container, bootstrap);

    expect(find.text('Checking…'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('check-runtime-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('runtime unavailable exposes Exit without retargeting', (
    tester,
  ) async {
    final bootstrap = FakeClientBootstrap();
    final runtime = FakeRuntimeApi();
    var terminated = 0;
    final container = await pumpView(
      tester,
      view: RuntimeUnavailableView(state: unavailableState(lastKnownId: 'a')),
      bootstrap: bootstrap,
      runtime: runtime,
      terminator: () => terminated++,
    );
    await seedFailed(tester, container, bootstrap);

    expect(
      find.byKey(const ValueKey<String>('runtime-unavailable-exit-button')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('runtime-unavailable-exit-button')),
    );
    await tester.pump();

    expect(terminated, 1);
    expect(runtime.getRuntimeStateCalls, 0);
    expect(runtime.exitRequests, isEmpty);
  });

  testWidgets('runtime unavailable reconciliation changes do not steal focus', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        clientBootstrapProvider.overrideWithValue(FakeClientBootstrap()),
        runtimeApiProvider.overrideWithValue(FakeRuntimeApi()),
        diagnosticsApiProvider.overrideWithValue(FakeDiagnosticsApi()),
        runtimeEventsProvider.overrideWithValue(FakeEventsApi()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: RuntimeUnavailableView(
            state: unavailableState(lastKnownId: 'a'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final check = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('check-runtime-button')),
    );
    expect(check.focusNode?.hasFocus, isTrue);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: RuntimeUnavailableView(
            state: unavailableState(
              lastKnownId: 'a',
              reconciliation: const ReconciliationOperationState.failed(
                TransportFailure('still unreachable'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('check-runtime-button')),
          )
          .focusNode
          ?.hasFocus,
      isTrue,
    );
  });

  testWidgets('recovery surface adapts at all width classes and text scales', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    for (final width in <double>[480, 720, 1024, 1440]) {
      for (final scale in <double>[1, 2]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        tester.binding.platformDispatcher.textScaleFactorTestValue = scale;

        final bootstrap = FakeClientBootstrap();
        final container = await pumpView(
          tester,
          view: StartupFailureView(state: failedStartupState(id: 'a')),
          bootstrap: bootstrap,
        );
        await seedFailed(tester, container, bootstrap);

        expect(
          find.byKey(
            const ValueKey<String>('reset-appearance-settings-button'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('recovery actions are keyboard-traversable', (tester) async {
    final bootstrap = FakeClientBootstrap();
    final container = await pumpView(
      tester,
      view: StartupFailureView(state: failedStartupState(id: 'a')),
      bootstrap: bootstrap,
    );
    await seedFailed(tester, container, bootstrap);

    final reset = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('reset-appearance-settings-button')),
    );
    expect(reset.focusNode?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      _controlHasFocus(tester, const ValueKey<String>('retry-startup-button')),
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      _controlHasFocus(
        tester,
        const ValueKey<String>('export-diagnostics-button'),
      ),
      isTrue,
    );
  });
}

bool _controlHasFocus(WidgetTester tester, Key key) {
  final primaryWidget =
      tester.binding.focusManager.primaryFocus?.context?.widget;
  if (primaryWidget == null) return false;
  return find
      .descendant(of: find.byKey(key), matching: find.byWidget(primaryWidget))
      .evaluate()
      .isNotEmpty;
}
