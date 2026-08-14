import 'dart:async';

import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'startup_test_fakes.dart';

void main() {
  ProviderContainer makeContainer({
    required FakeClientBootstrap bootstrap,
    required FakeRuntimeApi runtime,
    required FakeDiagnosticsApi diagnostics,
    required FakeEventsApi events,
  }) {
    final container = ProviderContainer(
      overrides: [
        clientBootstrapProvider.overrideWithValue(bootstrap),
        runtimeApiProvider.overrideWithValue(runtime),
        diagnosticsApiProvider.overrideWithValue(diagnostics),
        runtimeEventsProvider.overrideWithValue(events),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> settle() => pumpEventQueue();

  test('initial bootstrap reaches AsyncLoading then ready', () async {
    final bootstrap = FakeClientBootstrap();
    final container = makeContainer(
      bootstrap: bootstrap,
      runtime: FakeRuntimeApi(),
      diagnostics: FakeDiagnosticsApi(),
      events: FakeEventsApi(),
    );

    container.read(startupControllerProvider);
    await settle();
    expect(
      container.read(startupControllerProvider),
      isA<AsyncLoading<StartupState>>(),
    );

    bootstrap.completers.single.complete(
      RuntimeState.ready(runtimeInstanceId: testId('a')),
    );
    await settle();

    final async = container.read(startupControllerProvider);
    expect(async.hasError, isFalse);
    expect(async.value, isA<StartupStateReady>());
  });

  test('transported StartupFailed is loaded data, never AsyncError', () async {
    final bootstrap = FakeClientBootstrap();
    final container = makeContainer(
      bootstrap: bootstrap,
      runtime: FakeRuntimeApi(),
      diagnostics: FakeDiagnosticsApi(),
      events: FakeEventsApi(),
    );

    container.read(startupControllerProvider);
    await settle();
    bootstrap.completers.single.complete(failedRuntime(id: 'a'));
    await settle();

    final async = container.read(startupControllerProvider);
    expect(async.hasError, isFalse);
    final state = async.value as StartupStateStartupFailed;
    expect(state.runtimeInstanceId, testId('a'));
    expect(
      state.failure.error.code.value,
      'ARGUS.V1.CONFIGURATION.PERSISTED_SETTINGS_INVALID',
    );
  });

  test('initial TransportFailure stays a typed AsyncError', () async {
    final bootstrap = FakeClientBootstrap();
    final container = makeContainer(
      bootstrap: bootstrap,
      runtime: FakeRuntimeApi(),
      diagnostics: FakeDiagnosticsApi(),
      events: FakeEventsApi(),
    );

    container.read(startupControllerProvider);
    await settle();
    bootstrap.completers.single.completeError(
      const TransportFailure('native unavailable'),
      StackTrace.current,
    );
    await settle();

    final async = container.read(startupControllerProvider) as AsyncError;
    expect(async.error, isA<TransportFailure>());
  });

  test('initial ApplicationFailure stays a typed ApplicationFailure', () async {
    final bootstrap = FakeClientBootstrap();
    final container = makeContainer(
      bootstrap: bootstrap,
      runtime: FakeRuntimeApi(),
      diagnostics: FakeDiagnosticsApi(),
      events: FakeEventsApi(),
    );

    container.read(startupControllerProvider);
    await settle();
    bootstrap.completers.single.completeError(
      applicationFailure(),
      StackTrace.current,
    );
    await settle();

    final async = container.read(startupControllerProvider) as AsyncError;
    expect(async.error, isA<ApplicationFailure>());
  });

  test('retryInitialization is fresh, single-flight, and stale-safe', () async {
    final bootstrap = FakeClientBootstrap();
    final container = makeContainer(
      bootstrap: bootstrap,
      runtime: FakeRuntimeApi(),
      diagnostics: FakeDiagnosticsApi(),
      events: FakeEventsApi(),
    );
    final controller = container.read(startupControllerProvider.notifier);

    container.read(startupControllerProvider);
    await settle();
    bootstrap.completers.first.completeError(
      const TransportFailure('attempt A failed'),
      StackTrace.current,
    );
    await settle();

    final retryFuture = controller.retryInitialization();
    final duplicateFuture = controller.retryInitialization();
    await settle();

    expect(bootstrap.initializeCalls, 2);
    bootstrap.completers.last.complete(
      RuntimeState.ready(runtimeInstanceId: testId('b')),
    );
    await retryFuture;
    await duplicateFuture;
    await settle();

    expect(
      container.read(startupControllerProvider).value,
      isA<StartupStateReady>(),
    );
  });

  test('retryStartup is generation-bound and single-flight', () async {
    final bootstrap = FakeClientBootstrap();
    final runtime = FakeRuntimeApi();
    final container = makeContainer(
      bootstrap: bootstrap,
      runtime: runtime,
      diagnostics: FakeDiagnosticsApi(),
      events: FakeEventsApi(),
    );
    final controller = container.read(startupControllerProvider.notifier);

    container.read(startupControllerProvider);
    await settle();
    bootstrap.completers.single.complete(failedRuntime(id: 'a'));
    await settle();

    final first = controller.retryStartup();
    final duplicate = controller.retryStartup();
    await settle();

    expect(runtime.retryRequests, hasLength(1));
    expect(runtime.retryRequests.single.runtimeInstanceId, testId('a'));
    final running =
        container.read(startupControllerProvider).value
            as StartupStateStartupFailed;
    expect(running.recoveryOperation, isA<RecoveryOperationStateRunning>());
    expect(running.failure.recoveryActions, isNotEmpty);

    runtime.retryRequests.single.completer.complete(
      RuntimeState.ready(runtimeInstanceId: testId('b')),
    );
    await settle();
    await first;
    await duplicate;

    final adopted = container.read(startupControllerProvider).value;
    expect(adopted, isA<StartupStateReady>());
    expect((adopted as StartupStateReady).runtimeInstanceId, testId('b'));
  });

  test(
    'resetAppearanceSettings is single-flight and adopts replacement',
    () async {
      final bootstrap = FakeClientBootstrap();
      final runtime = FakeRuntimeApi();
      final container = makeContainer(
        bootstrap: bootstrap,
        runtime: runtime,
        diagnostics: FakeDiagnosticsApi(),
        events: FakeEventsApi(),
      );
      final controller = container.read(startupControllerProvider.notifier);

      container.read(startupControllerProvider);
      await settle();
      bootstrap.completers.single.complete(
        failedRuntime(
          id: 'a',
          actions: const <RecoveryActionKind>[
            RecoveryActionKind.resetAppearanceSettings,
            RecoveryActionKind.exit,
          ],
        ),
      );
      await settle();

      final first = controller.resetAppearanceSettings();
      final duplicate = controller.resetAppearanceSettings();
      await settle();

      expect(runtime.resetRequests, hasLength(1));
      runtime.resetRequests.single.completer.complete(
        RuntimeState.ready(runtimeInstanceId: testId('b')),
      );
      await settle();
      await first;
      await duplicate;

      expect(
        container.read(startupControllerProvider).value,
        isA<StartupStateReady>(),
      );
    },
  );

  test('actions absent from the failure are never invoked', () async {
    final bootstrap = FakeClientBootstrap();
    final runtime = FakeRuntimeApi();
    final diagnostics = FakeDiagnosticsApi();
    final container = makeContainer(
      bootstrap: bootstrap,
      runtime: runtime,
      diagnostics: diagnostics,
      events: FakeEventsApi(),
    );
    final controller = container.read(startupControllerProvider.notifier);

    container.read(startupControllerProvider);
    await settle();
    bootstrap.completers.single.complete(
      failedRuntime(
        id: 'a',
        actions: const <RecoveryActionKind>[RecoveryActionKind.exit],
      ),
    );
    await settle();

    await controller.retryStartup();
    await controller.resetAppearanceSettings();
    await controller.exportDiagnostics(destination: '/tmp/x.zip');
    await controller.loadTechnicalDetails();
    await controller.openDataDirectory();
    await settle();

    expect(runtime.retryRequests, isEmpty);
    expect(runtime.resetRequests, isEmpty);
    expect(diagnostics.exportRequests, isEmpty);
    expect(diagnostics.detailsRequests, isEmpty);
    expect(diagnostics.openRequests, isEmpty);
  });

  test('stale retry reconciles authoritative state without replay', () async {
    final bootstrap = FakeClientBootstrap();
    final runtime = FakeRuntimeApi()
      ..getRuntimeStateResult = RuntimeState.ready(
        runtimeInstanceId: testId('b'),
      );
    final container = makeContainer(
      bootstrap: bootstrap,
      runtime: runtime,
      diagnostics: FakeDiagnosticsApi(),
      events: FakeEventsApi(),
    );
    final controller = container.read(startupControllerProvider.notifier);

    container.read(startupControllerProvider);
    await settle();
    bootstrap.completers.single.complete(failedRuntime(id: 'a'));
    await settle();

    final retry = controller.retryStartup();
    await settle();
    runtime.retryRequests.single.completer.completeError(
      staleInstanceFailure(),
      StackTrace.current,
    );
    await retry;
    await settle();

    expect(runtime.retryRequests, hasLength(1));
    expect(runtime.getRuntimeStateCalls, 1);
    expect(
      container.read(startupControllerProvider).value,
      isA<StartupStateReady>(),
    );
  });

  test('ambiguous retry outcome reconciles and never replays', () async {
    final bootstrap = FakeClientBootstrap();
    final runtime = FakeRuntimeApi()
      ..getRuntimeStateResult = RuntimeState.ready(
        runtimeInstanceId: testId('b'),
      );
    final container = makeContainer(
      bootstrap: bootstrap,
      runtime: runtime,
      diagnostics: FakeDiagnosticsApi(),
      events: FakeEventsApi(),
    );
    final controller = container.read(startupControllerProvider.notifier);

    container.read(startupControllerProvider);
    await settle();
    bootstrap.completers.single.complete(failedRuntime(id: 'a'));
    await settle();

    final retry = controller.retryStartup();
    await settle();
    runtime.retryRequests.single.completer.completeError(
      const TransportFailure('ambiguous transport outcome'),
      StackTrace.current,
    );
    await retry;
    await settle();

    expect(runtime.retryRequests, hasLength(1));
    expect(runtime.getRuntimeStateCalls, 1);
    final adopted = container.read(startupControllerProvider).value;
    expect(adopted, isA<StartupStateReady>());
    expect((adopted as StartupStateReady).runtimeInstanceId, testId('b'));
  });

  test(
    'failed reconciliation keeps last-known context and reports failure',
    () async {
      final bootstrap = FakeClientBootstrap();
      final runtime = FakeRuntimeApi()
        ..getRuntimeStateError = const TransportFailure('still unreachable');
      final container = makeContainer(
        bootstrap: bootstrap,
        runtime: runtime,
        diagnostics: FakeDiagnosticsApi(),
        events: FakeEventsApi(),
      );
      final controller = container.read(startupControllerProvider.notifier);

      container.read(startupControllerProvider);
      await settle();
      bootstrap.completers.single.complete(failedRuntime(id: 'a'));
      await settle();

      final retry = controller.retryStartup();
      await settle();
      runtime.retryRequests.single.completer.completeError(
        const TransportFailure('ambiguous transport outcome'),
        StackTrace.current,
      );
      await retry;
      await settle();

      final unavailable =
          container.read(startupControllerProvider).value
              as StartupStateRuntimeUnavailable;
      expect(unavailable.lastKnownRuntime?.runtimeInstanceId, testId('a'));
      expect(
        unavailable.reconciliationOperation,
        isA<ReconciliationOperationStateFailed>(),
      );
    },
  );

  test('runtimeUnavailable check is single-flight and stale-safe', () async {
    final bootstrap = FakeClientBootstrap();
    final runtime = FakeRuntimeApi()
      ..getRuntimeStateError = const TransportFailure('still unreachable');
    final container = makeContainer(
      bootstrap: bootstrap,
      runtime: runtime,
      diagnostics: FakeDiagnosticsApi(),
      events: FakeEventsApi(),
    );
    final controller = container.read(startupControllerProvider.notifier);

    container.read(startupControllerProvider);
    await settle();
    bootstrap.completers.single.complete(failedRuntime(id: 'a'));
    await settle();
    final retry = controller.retryStartup();
    await settle();
    runtime.retryRequests.single.completer.completeError(
      const TransportFailure('ambiguous transport outcome'),
      StackTrace.current,
    );
    await retry;
    await settle();
    expect(
      container.read(startupControllerProvider).value,
      isA<StartupStateRuntimeUnavailable>(),
    );

    runtime.getRuntimeStateError = null;
    final completer = Completer<RuntimeState>();
    runtime.getRuntimeStateCompleter = completer;
    final first = controller.reconcileRuntime();
    final duplicate = controller.reconcileRuntime();
    await settle();

    expect(runtime.getRuntimeStateCalls, 2);
    final running =
        container.read(startupControllerProvider).value
            as StartupStateRuntimeUnavailable;
    expect(
      running.reconciliationOperation,
      isA<ReconciliationOperationStateRunning>(),
    );

    completer.complete(RuntimeState.ready(runtimeInstanceId: testId('b')));
    await settle();
    await first;
    await duplicate;
    expect(
      container.read(startupControllerProvider).value,
      isA<StartupStateReady>(),
    );
  });

  test(
    'export keeps failure authoritative and reports operation state',
    () async {
      final bootstrap = FakeClientBootstrap();
      final diagnostics = FakeDiagnosticsApi();
      final container = makeContainer(
        bootstrap: bootstrap,
        runtime: FakeRuntimeApi(),
        diagnostics: diagnostics,
        events: FakeEventsApi(),
      );
      final controller = container.read(startupControllerProvider.notifier);

      container.read(startupControllerProvider);
      await settle();
      bootstrap.completers.single.complete(failedRuntime(id: 'a'));
      await settle();

      final request = controller.exportDiagnostics(destination: '/tmp/out.zip');
      await settle();
      expect(diagnostics.exportRequests, hasLength(1));
      expect(diagnostics.exportDestinations.single, '/tmp/out.zip');
      var running =
          container.read(startupControllerProvider).value
              as StartupStateStartupFailed;
      expect(running.exportOperation, isA<ExportOperationStateRunning>());

      diagnostics.exportRequests.single.completer.complete(
        RuntimeState.ready(runtimeInstanceId: testId('b')),
      );
      await settle();
      await request;
      running =
          container.read(startupControllerProvider).value
              as StartupStateStartupFailed;
      expect(running.exportOperation, isA<ExportOperationStateSucceeded>());
      expect(running.runtimeInstanceId, testId('a'));
    },
  );

  test('export failure is scoped and keeps the original failure', () async {
    final bootstrap = FakeClientBootstrap();
    final diagnostics = FakeDiagnosticsApi();
    final container = makeContainer(
      bootstrap: bootstrap,
      runtime: FakeRuntimeApi(),
      diagnostics: diagnostics,
      events: FakeEventsApi(),
    );
    final controller = container.read(startupControllerProvider.notifier);

    container.read(startupControllerProvider);
    await settle();
    bootstrap.completers.single.complete(failedRuntime(id: 'a'));
    await settle();

    final export = controller.exportDiagnostics(destination: '/tmp/out.zip');
    await settle();
    diagnostics.exportRequests.single.completer.completeError(
      applicationFailure(messageKey: 'errors.filesystem.permission_denied'),
      StackTrace.current,
    );
    await export;
    await settle();

    final state =
        container.read(startupControllerProvider).value
            as StartupStateStartupFailed;
    expect(state.exportOperation, isA<ExportOperationStateFailed>());
    expect(state.failure.error.code.value, isNotEmpty);
  });

  test('stale export reconciles without retargeting', () async {
    final bootstrap = FakeClientBootstrap();
    final runtime = FakeRuntimeApi()
      ..getRuntimeStateResult = RuntimeState.ready(
        runtimeInstanceId: testId('b'),
      );
    final diagnostics = FakeDiagnosticsApi();
    final container = makeContainer(
      bootstrap: bootstrap,
      runtime: runtime,
      diagnostics: diagnostics,
      events: FakeEventsApi(),
    );
    final controller = container.read(startupControllerProvider.notifier);

    container.read(startupControllerProvider);
    await settle();
    bootstrap.completers.single.complete(failedRuntime(id: 'a'));
    await settle();

    final export = controller.exportDiagnostics(destination: '/tmp/out.zip');
    await settle();
    diagnostics.exportRequests.single.completer.completeError(
      staleInstanceFailure(),
      StackTrace.current,
    );
    await export;
    await settle();

    expect(runtime.getRuntimeStateCalls, 1);
    expect(
      container.read(startupControllerProvider).value,
      isA<StartupStateReady>(),
    );
  });

  test('late old-generation export cannot publish after replacement', () async {
    final bootstrap = FakeClientBootstrap();
    final runtime = FakeRuntimeApi();
    final diagnostics = FakeDiagnosticsApi();
    final container = makeContainer(
      bootstrap: bootstrap,
      runtime: runtime,
      diagnostics: diagnostics,
      events: FakeEventsApi(),
    );
    final controller = container.read(startupControllerProvider.notifier);

    container.read(startupControllerProvider);
    await settle();
    bootstrap.completers.single.complete(failedRuntime(id: 'a'));
    await settle();

    final export = controller.exportDiagnostics(destination: '/tmp/out.zip');
    final retry = controller.retryStartup();
    await settle();
    runtime.retryRequests.single.completer.complete(
      RuntimeState.ready(runtimeInstanceId: testId('b')),
    );
    await settle();
    await retry;

    diagnostics.exportRequests.single.completer.complete(
      RuntimeState.ready(runtimeInstanceId: testId('a')),
    );
    await settle();
    await export;

    final adopted = container.read(startupControllerProvider).value;
    expect(adopted, isA<StartupStateReady>());
    expect((adopted as StartupStateReady).runtimeInstanceId, testId('b'));
  });

  test('technical details load lazily and clear on replacement', () async {
    final bootstrap = FakeClientBootstrap();
    final runtime = FakeRuntimeApi();
    final diagnostics = FakeDiagnosticsApi();
    final container = makeContainer(
      bootstrap: bootstrap,
      runtime: runtime,
      diagnostics: diagnostics,
      events: FakeEventsApi(),
    );
    final controller = container.read(startupControllerProvider.notifier);

    container.read(startupControllerProvider);
    await settle();
    bootstrap.completers.single.complete(failedRuntime(id: 'a'));
    await settle();

    final load = controller.loadTechnicalDetails();
    await settle();
    expect(diagnostics.detailsRequests, hasLength(1));
    diagnostics.detailsRequests.single.completer.complete(
      RuntimeState.ready(runtimeInstanceId: testId('a')),
    );
    await settle();
    await load;

    var state =
        container.read(startupControllerProvider).value
            as StartupStateStartupFailed;
    expect(state.technicalDetails, isA<TechnicalDetailsOperationStateLoaded>());

    final retry = controller.retryStartup();
    await settle();
    runtime.retryRequests.single.completer.complete(
      RuntimeState.ready(runtimeInstanceId: testId('b')),
    );
    await settle();
    await retry;

    expect(
      container.read(startupControllerProvider).value,
      isA<StartupStateReady>(),
    );
  });

  test('details load failure does not erase the startup failure', () async {
    final bootstrap = FakeClientBootstrap();
    final diagnostics = FakeDiagnosticsApi();
    final container = makeContainer(
      bootstrap: bootstrap,
      runtime: FakeRuntimeApi(),
      diagnostics: diagnostics,
      events: FakeEventsApi(),
    );
    final controller = container.read(startupControllerProvider.notifier);

    container.read(startupControllerProvider);
    await settle();
    bootstrap.completers.single.complete(failedRuntime(id: 'a'));
    await settle();

    final load = controller.loadTechnicalDetails();
    await settle();
    diagnostics.detailsRequests.single.completer.completeError(
      const TransportFailure('details transport failed'),
      StackTrace.current,
    );
    await load;
    await settle();

    final state =
        container.read(startupControllerProvider).value
            as StartupStateStartupFailed;
    expect(state.technicalDetails, isA<TechnicalDetailsOperationStateFailed>());
    expect(state.runtimeInstanceId, testId('a'));
  });

  test('open data directory reports running, success, and failure', () async {
    final bootstrap = FakeClientBootstrap();
    final diagnostics = FakeDiagnosticsApi();
    final container = makeContainer(
      bootstrap: bootstrap,
      runtime: FakeRuntimeApi(),
      diagnostics: diagnostics,
      events: FakeEventsApi(),
    );
    final controller = container.read(startupControllerProvider.notifier);

    container.read(startupControllerProvider);
    await settle();
    bootstrap.completers.single.complete(failedRuntime(id: 'a'));
    await settle();

    final open = controller.openDataDirectory();
    await settle();
    expect(diagnostics.openRequests, hasLength(1));
    diagnostics.openRequests.single.completer.complete(
      RuntimeState.ready(runtimeInstanceId: testId('a')),
    );
    await settle();
    await open;

    var state =
        container.read(startupControllerProvider).value
            as StartupStateStartupFailed;
    expect(
      state.openDirectoryOperation,
      isA<OpenDirectoryOperationStateIdle>(),
    );

    final openAgain = controller.openDataDirectory();
    await settle();
    diagnostics.openRequests.last.completer.completeError(
      const TransportFailure('open failed'),
      StackTrace.current,
    );
    await openAgain;
    await settle();
    state =
        container.read(startupControllerProvider).value
            as StartupStateStartupFailed;
    expect(
      state.openDirectoryOperation,
      isA<OpenDirectoryOperationStateFailed>(),
    );
  });

  test('exit adopts authoritative stopped state', () async {
    final bootstrap = FakeClientBootstrap();
    final runtime = FakeRuntimeApi();
    final container = makeContainer(
      bootstrap: bootstrap,
      runtime: runtime,
      diagnostics: FakeDiagnosticsApi(),
      events: FakeEventsApi(),
    );
    final controller = container.read(startupControllerProvider.notifier);

    container.read(startupControllerProvider);
    await settle();
    bootstrap.completers.single.complete(failedRuntime(id: 'a'));
    await settle();

    final exit = controller.requestExit();
    await settle();
    expect(runtime.exitRequests, hasLength(1));
    runtime.exitRequests.single.completer.complete(
      RuntimeState.stopped(runtimeInstanceId: testId('a')),
    );
    await settle();
    await exit;

    expect(
      container.read(startupControllerProvider).value,
      isA<StartupStateStopped>(),
    );
  });

  test('runtime notifications accelerate but are never required', () async {
    final bootstrap = FakeClientBootstrap();
    final runtime = FakeRuntimeApi()
      ..getRuntimeStateResult = RuntimeState.ready(
        runtimeInstanceId: testId('b'),
      );
    final events = FakeEventsApi();
    final container = makeContainer(
      bootstrap: bootstrap,
      runtime: runtime,
      diagnostics: FakeDiagnosticsApi(),
      events: events,
    );

    container.read(startupControllerProvider);
    await settle();
    bootstrap.completers.single.complete(failedRuntime(id: 'a'));
    await settle();

    events.emit(
      RuntimeEvent(
        runtimeInstanceId: testId('a'),
        sequence: BigInt.one,
        occurredAtMs: BigInt.one,
        payload: const RuntimeEventPayload.runtimeStateChanged(
          lifecycle: RuntimeLifecycle.ready,
        ),
      ),
    );
    await settle();

    expect(runtime.getRuntimeStateCalls, 1);
    expect(
      container.read(startupControllerProvider).value,
      isA<StartupStateReady>(),
    );

    // AppearanceSettingsChanged is not a startup reconciliation hint.
    events.emit(
      RuntimeEvent(
        runtimeInstanceId: testId('b'),
        sequence: BigInt.from(2),
        occurredAtMs: BigInt.from(2),
        payload: const RuntimeEventPayload.appearanceSettingsChanged(),
      ),
    );
    await settle();
    expect(runtime.getRuntimeStateCalls, 1);

    // Once Ready, event hints and stream errors cannot regress the shell.
    events.emit(
      RuntimeEvent(
        runtimeInstanceId: testId('b'),
        sequence: BigInt.from(3),
        occurredAtMs: BigInt.from(3),
        payload: const RuntimeEventPayload.runtimeStateChanged(
          lifecycle: RuntimeLifecycle.shuttingDown,
        ),
      ),
    );
    events.emitError(const TransportFailure('event stream degraded'));
    await settle();
    expect(runtime.getRuntimeStateCalls, 1);
    expect(
      container.read(startupControllerProvider).value,
      isA<StartupStateReady>(),
    );
  });

  test(
    'runtime A shutdown notifications during retry never reconcile',
    () async {
      final bootstrap = FakeClientBootstrap();
      final runtime = FakeRuntimeApi();
      final events = FakeEventsApi();
      final container = makeContainer(
        bootstrap: bootstrap,
        runtime: runtime,
        diagnostics: FakeDiagnosticsApi(),
        events: events,
      );
      final controller = container.read(startupControllerProvider.notifier);

      container.read(startupControllerProvider);
      await settle();
      bootstrap.completers.single.complete(failedRuntime(id: 'a'));
      await settle();

      final retry = controller.retryStartup();
      await settle();
      expect(runtime.retryRequests, hasLength(1));
      final callsBefore = runtime.getRuntimeStateCalls;

      events.emit(_runtimeEvent(testId('a'), RuntimeLifecycle.shuttingDown));
      events.emit(_runtimeEvent(testId('a'), RuntimeLifecycle.stopped));
      await settle();

      expect(runtime.getRuntimeStateCalls, callsBefore);
      var state =
          container.read(startupControllerProvider).value
              as StartupStateStartupFailed;
      expect(state.runtimeInstanceId, testId('a'));
      expect(state.recoveryOperation, isA<RecoveryOperationStateRunning>());

      runtime.retryRequests.single.completer.complete(
        RuntimeState.ready(runtimeInstanceId: testId('b')),
      );
      await retry;
      await settle();
      expect(
        container.read(startupControllerProvider).value,
        isA<StartupStateReady>(),
      );
    },
  );

  test(
    'runtime A stopped notifications during reset never reconcile',
    () async {
      final bootstrap = FakeClientBootstrap();
      final runtime = FakeRuntimeApi();
      final events = FakeEventsApi();
      final container = makeContainer(
        bootstrap: bootstrap,
        runtime: runtime,
        diagnostics: FakeDiagnosticsApi(),
        events: events,
      );
      final controller = container.read(startupControllerProvider.notifier);

      container.read(startupControllerProvider);
      await settle();
      bootstrap.completers.single.complete(
        failedRuntime(
          id: 'a',
          actions: const <RecoveryActionKind>[
            RecoveryActionKind.resetAppearanceSettings,
            RecoveryActionKind.exit,
          ],
        ),
      );
      await settle();

      final reset = controller.resetAppearanceSettings();
      await settle();
      expect(runtime.resetRequests, hasLength(1));
      final callsBefore = runtime.getRuntimeStateCalls;

      events.emit(_runtimeEvent(testId('a'), RuntimeLifecycle.stopped));
      await settle();

      expect(runtime.getRuntimeStateCalls, callsBefore);
      var state =
          container.read(startupControllerProvider).value
              as StartupStateStartupFailed;
      expect(state.runtimeInstanceId, testId('a'));
      expect(state.recoveryOperation, isA<RecoveryOperationStateRunning>());

      runtime.resetRequests.single.completer.complete(
        RuntimeState.ready(runtimeInstanceId: testId('b')),
      );
      await reset;
      await settle();
      expect(
        container.read(startupControllerProvider).value,
        isA<StartupStateReady>(),
      );
    },
  );

  test('runtime A stopped notifications during exit never reconcile', () async {
    final bootstrap = FakeClientBootstrap();
    final runtime = FakeRuntimeApi();
    final events = FakeEventsApi();
    final container = makeContainer(
      bootstrap: bootstrap,
      runtime: runtime,
      diagnostics: FakeDiagnosticsApi(),
      events: events,
    );
    final controller = container.read(startupControllerProvider.notifier);

    container.read(startupControllerProvider);
    await settle();
    bootstrap.completers.single.complete(failedRuntime(id: 'a'));
    await settle();

    final exit = controller.requestExit();
    await settle();
    expect(runtime.exitRequests, hasLength(1));
    final callsBefore = runtime.getRuntimeStateCalls;

    events.emit(_runtimeEvent(testId('a'), RuntimeLifecycle.stopped));
    await settle();

    expect(runtime.getRuntimeStateCalls, callsBefore);
    var state =
        container.read(startupControllerProvider).value
            as StartupStateStartupFailed;
    expect(state.recoveryOperation, isA<RecoveryOperationStateRunning>());

    runtime.exitRequests.single.completer.complete(
      RuntimeState.stopped(runtimeInstanceId: testId('a')),
    );
    await exit;
    await settle();
    expect(
      container.read(startupControllerProvider).value,
      isA<StartupStateStopped>(),
    );
  });

  test(
    'same-generation refresh preserves failed-runtime local state',
    () async {
      final bootstrap = FakeClientBootstrap();
      final runtime = FakeRuntimeApi()
        ..getRuntimeStateResult = failedRuntime(id: 'a');
      final diagnostics = FakeDiagnosticsApi();
      final events = FakeEventsApi();
      final container = makeContainer(
        bootstrap: bootstrap,
        runtime: runtime,
        diagnostics: diagnostics,
        events: events,
      );
      final controller = container.read(startupControllerProvider.notifier);

      container.read(startupControllerProvider);
      await settle();
      bootstrap.completers.single.complete(failedRuntime(id: 'a'));
      await settle();

      final details = controller.loadTechnicalDetails();
      await settle();
      diagnostics.detailsRequests.single.completer.complete(
        RuntimeState.ready(runtimeInstanceId: testId('a')),
      );
      await details;

      final export = controller.exportDiagnostics(destination: '/tmp/out.zip');
      await settle();
      diagnostics.exportRequests.single.completer.complete(
        RuntimeState.ready(runtimeInstanceId: testId('a')),
      );
      await export;

      final open = controller.openDataDirectory();
      await settle();
      diagnostics.openRequests.single.completer.completeError(
        const TransportFailure('open failed'),
        StackTrace.current,
      );
      await open;

      final failedRetry = controller.retryStartup();
      await settle();
      runtime.retryRequests.single.completer.completeError(
        applicationFailure(),
        StackTrace.current,
      );
      await failedRetry;

      events.emit(_runtimeEvent(testId('a'), RuntimeLifecycle.startupFailed));
      await settle();

      expect(runtime.getRuntimeStateCalls, 1);
      final state =
          container.read(startupControllerProvider).value
              as StartupStateStartupFailed;
      expect(state.runtimeInstanceId, testId('a'));
      expect(
        state.technicalDetails,
        isA<TechnicalDetailsOperationStateLoaded>(),
      );
      expect(state.exportOperation, isA<ExportOperationStateSucceeded>());
      expect(
        state.openDirectoryOperation,
        isA<OpenDirectoryOperationStateFailed>(),
      );
      expect(state.recoveryOperation, isA<RecoveryOperationStateFailed>());
    },
  );

  test('no new diagnostics are admitted while recovery is running', () async {
    final bootstrap = FakeClientBootstrap();
    final runtime = FakeRuntimeApi();
    final diagnostics = FakeDiagnosticsApi();
    final container = makeContainer(
      bootstrap: bootstrap,
      runtime: runtime,
      diagnostics: diagnostics,
      events: FakeEventsApi(),
    );
    final controller = container.read(startupControllerProvider.notifier);

    container.read(startupControllerProvider);
    await settle();
    bootstrap.completers.single.complete(failedRuntime(id: 'a'));
    await settle();

    final retry = controller.retryStartup();
    await settle();
    expect(runtime.retryRequests, hasLength(1));

    await controller.exportDiagnostics(destination: '/tmp/out.zip');
    await controller.loadTechnicalDetails();
    await controller.openDataDirectory();

    expect(diagnostics.exportRequests, isEmpty);
    expect(diagnostics.detailsRequests, isEmpty);
    expect(diagnostics.openRequests, isEmpty);

    runtime.retryRequests.single.completer.complete(
      RuntimeState.ready(runtimeInstanceId: testId('b')),
    );
    await retry;
  });

  test(
    'root-client replacement resubscribes exactly once to the new stream',
    () async {
      final gatewayA = CountingGateway(testId('a'));
      final gatewayB = CountingGateway(testId('b'));
      var gatewayIndex = 0;
      final container = ProviderContainer(
        overrides: [
          argusClientGatewayFactoryProvider.overrideWithValue(
            () => gatewayIndex++ == 0 ? gatewayA : gatewayB,
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(startupControllerProvider);
      await settle();
      expect(
        container.read(startupControllerProvider).value,
        isA<StartupStateReady>(),
      );
      expect(gatewayA.listenCount, 1);

      final controller = container.read(startupControllerProvider.notifier);
      final retry = controller.retryInitialization();
      await retry;
      await settle();

      expect(gatewayB.listenCount, 1);
      // The closed old mapped stream never triggers a resubscription loop.
      expect(gatewayA.listenCount, 1);
      expect(gatewayB.listenCount, 1);
    },
  );
}

RuntimeEvent _runtimeEvent(RuntimeInstanceId id, RuntimeLifecycle lifecycle) =>
    RuntimeEvent(
      runtimeInstanceId: id,
      sequence: BigInt.one,
      occurredAtMs: BigInt.one,
      payload: RuntimeEventPayload.runtimeStateChanged(lifecycle: lifecycle),
    );
