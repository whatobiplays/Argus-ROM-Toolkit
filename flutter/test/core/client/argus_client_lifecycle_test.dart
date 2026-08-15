import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'jobs_gateway_stub.dart';
import 'sources_gateway_stub.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('late replacement subscription attaching after shutdown cannot hang '
      'teardown', () async {
    final gateway = _ControlledGateway()..state = _failedA();
    final client = ArgusClient(gateway: gateway);

    final initialize = client.initialize();
    await pumpEventQueue();
    gateway.startTask(0);
    await initialize;

    final reset = client.runtime.resetAppearanceSettings(_idA);
    await pumpEventQueue();
    // The client bound generation B; its native task has not attached yet.
    expect(gateway.tasks, hasLength(2));

    final shutdown = client.runtime.generalShutdown();
    // The B task attaches after shutdown closed the boundary; the bridge
    // must reject it immediately instead of parking forever.
    gateway.startTask(1);
    await reset;
    await shutdown;

    await client.dispose();
    // Shutdown teardown closes/invalidates the native connection; disposal
    // then completes deterministically with no second close.
    expect(gateway.closeEventConnectionCalls, 1);
  });

  test(
    'dispose without explicit shutdown closes the live native connection',
    () async {
      final gateway = _ControlledGateway();
      final client = ArgusClient(gateway: gateway);

      final initialize = client.initialize();
      await pumpEventQueue();
      gateway.startTask(0);
      await initialize;

      final dispose = client.dispose();
      await pumpEventQueue();

      expect(gateway.closeEventConnectionCalls, 1);
      await dispose;
    },
  );

  test('shutdown closing the stream never schedules a reconnect', () async {
    final gateway = _ControlledGateway();
    final client = ArgusClient(gateway: gateway);

    final initialize = client.initialize();
    await pumpEventQueue();
    gateway.startTask(0);
    await initialize;

    await client.runtime.generalShutdown();
    await client.dispose();

    expect(gateway.tasks, hasLength(1));
  });

  test('dispose prevents any later reconnect or bind', () async {
    final gateway = _ControlledGateway();
    final client = ArgusClient(gateway: gateway);

    final initialize = client.initialize();
    await pumpEventQueue();
    gateway.startTask(0);
    await initialize;
    await client.dispose();

    await client.reconnectEvents();
    await expectLater(client.initialize(), throwsA(isA<TransportFailure>()));
    expect(gateway.tasks, hasLength(1));
  });

  test(
    'unexpected transport errors still trigger exactly one reconnect',
    () async {
      final gateway = _ControlledGateway();
      final client = ArgusClient(gateway: gateway);

      final initialize = client.initialize();
      await pumpEventQueue();
      gateway.startTask(0);
      await initialize;
      gateway.tasks[0].addError(const TransportFailure('transport broken'));
      await pumpEventQueue();
      await pumpEventQueue();

      expect(gateway.tasks, hasLength(2));
      gateway.startTask(1);
      await client.dispose();
    },
  );

  test('repeated shutdown and dispose remain idempotent', () async {
    final gateway = _ControlledGateway();
    final client = ArgusClient(gateway: gateway);

    final initialize = client.initialize();
    await pumpEventQueue();
    gateway.startTask(0);
    await initialize;

    await client.runtime.generalShutdown();
    await client.runtime.generalShutdown();
    expect(gateway.generalShutdownCalls, 2);

    await client.dispose();
    await client.dispose();
    // Each shutdown teardown performs one native close; disposal after
    // shutdown has no live subscription left to close.
    expect(gateway.closeEventConnectionCalls, 2);
  });

  test(
    'failed generalShutdown still closes the native connection and preserves '
    'the primary error',
    () async {
      final gateway = _ControlledGateway()..failShutdown = true;
      final client = ArgusClient(gateway: gateway);

      final initialize = client.initialize();
      await pumpEventQueue();
      gateway.startTask(0);
      await initialize;

      await expectLater(
        client.runtime.generalShutdown(),
        throwsA(isA<TransportFailure>()),
      );
      expect(gateway.tasks[0].ended, isTrue);
      expect(gateway.closeEventConnectionCalls, 1);

      await client.dispose();
    },
  );

  test(
    'direct dispose rejects a delayed native attach and leaves no connections',
    () async {
      final gateway = _ControlledGateway();
      final client = ArgusClient(gateway: gateway);

      final initialize = client.initialize();
      await pumpEventQueue();
      gateway.startTask(0);
      await initialize;
      final reset = client.runtime.resetAppearanceSettings(_idA);
      await pumpEventQueue();
      // The client bound generation B; its native task has not attached yet.
      expect(gateway.tasks, hasLength(2));

      final dispose = client.dispose();
      await pumpEventQueue();
      expect(gateway.closeEventConnectionCalls, 1);

      // The delayed native subscription attempts to attach after teardown;
      // teardown must have invalidated it through the same production close
      // mechanism, with no manual boundary flag.
      gateway.startTask(1);
      await dispose;
      await reset;

      expect(gateway.tasks[1].ended, isTrue);
      expect(
        gateway.tasks.where((task) => task.started && !task.ended),
        isEmpty,
      );
    },
  );

  test(
    'late native attach after dispose close cannot survive disposal',
    () async {
      final gateway = _ControlledGateway()..readEpochAtAttach = true;
      final client = ArgusClient(gateway: gateway);

      final initialize = client.initialize();
      await pumpEventQueue();
      gateway.startTask(0);
      await initialize;
      expect(gateway.tasks[0].attached, isTrue);

      // Bind B starts; its epoch/attachment acquisition remains pending.
      final reset = client.runtime.resetAppearanceSettings(_idA);
      await pumpEventQueue();
      expect(gateway.tasks, hasLength(2));
      expect(gateway.tasks[1].attached, isFalse);

      final dispose = client.dispose();
      await pumpEventQueue();
      expect(gateway.closeEventConnectionCalls, 1);

      // The pending bind now acquires the CURRENT (post-close) epoch and
      // establishes a native connection, exactly like the production gateway
      // reading the attach epoch after teardown already closed.
      gateway.startTask(1);
      await dispose;
      await reset;

      expect(gateway.tasks[1].attached, isTrue);
      expect(gateway.tasks[1].ended, isTrue);
      expect(
        gateway.tasks.where((task) => task.started && !task.ended),
        isEmpty,
      );
    },
  );

  test(
    'dispose surfaces a typed failure from the late cleanup close',
    () async {
      final gateway = _ControlledGateway()
        ..readEpochAtAttach = true
        ..closeFailure = _applicationFailure()
        ..failCloseOnCall = 2;
      final client = ArgusClient(gateway: gateway);

      final initialize = client.initialize();
      await pumpEventQueue();
      gateway.startTask(0);
      await initialize;

      final reset = client.runtime.resetAppearanceSettings(_idA);
      await pumpEventQueue();
      expect(gateway.tasks, hasLength(2));

      final dispose = client.dispose();
      await pumpEventQueue();
      expect(gateway.closeEventConnectionCalls, 1);

      // The pending bind attaches after the first close; its cleanup close
      // physically closes the connection but reports a typed failure.
      gateway.startTask(1);
      await expectLater(dispose, throwsA(isA<ApplicationFailure>()));
      await expectLater(reset, completes);

      expect(gateway.tasks[1].ended, isTrue);
      expect(gateway.closeEventConnectionCalls, 2);
      expect(
        gateway.tasks.where((task) => task.started && !task.ended),
        isEmpty,
      );
    },
  );

  test(
    'shutdown primary failure wins over late cleanup close failure',
    () async {
      final gateway = _ControlledGateway()
        ..readEpochAtAttach = true
        ..failShutdown = true
        ..closeFailure = _applicationFailure()
        ..failCloseOnCall = 2;
      final client = ArgusClient(gateway: gateway);

      final initialize = client.initialize();
      await pumpEventQueue();
      gateway.startTask(0);
      await initialize;

      final reset = client.runtime.resetAppearanceSettings(_idA);
      await pumpEventQueue();

      final shutdown = client.runtime.generalShutdown();
      gateway.startTask(1);
      await expectLater(shutdown, throwsA(isA<TransportFailure>()));
      await expectLater(reset, completes);

      expect(gateway.tasks[1].ended, isTrue);
      expect(gateway.closeEventConnectionCalls, 2);
    },
  );

  test(
    'shutdown surfaces late cleanup close failure over cancellation failure',
    () async {
      final gateway = _ControlledGateway()
        ..readEpochAtAttach = true
        ..closeBoundaryOnShutdown = false
        ..closeFailure = _applicationFailure()
        ..failCloseOnCall = 2
        ..lateCancelFailure = const TransportFailure('stale cancel failed');
      final client = ArgusClient(gateway: gateway);

      final initialize = client.initialize();
      await pumpEventQueue();
      gateway.startTask(0);
      await initialize;

      final reset = client.runtime.resetAppearanceSettings(_idA);
      await pumpEventQueue();

      final shutdown = client.runtime.generalShutdown();
      gateway.startTask(1);
      await expectLater(shutdown, throwsA(isA<ApplicationFailure>()));
      await expectLater(reset, completes);

      expect(gateway.tasks[1].ended, isTrue);
      expect(gateway.closeEventConnectionCalls, 2);
    },
  );

  test(
    'reconnect queued before shutdown rechecks state and publishes nothing',
    () async {
      final gateway = _ControlledGateway()..syncStreams = true;
      final client = ArgusClient(gateway: gateway);
      final errors = <Object>[];
      client.events.events.listen(null, onError: errors.add);

      final initialize = client.initialize();
      await pumpEventQueue();
      gateway.startTask(0);
      await initialize;
      // Synchronous error delivery schedules the reconnect microtask before
      // shutdown begins.
      gateway.tasks[0].addError(const TransportFailure('transport broken'));

      final shutdown = client.runtime.generalShutdown();
      await shutdown;
      await pumpEventQueue();

      expect(gateway.tasks, hasLength(1));
      // Only the original genuine transport error is published; the queued
      // reconnect neither rebinds nor emits a synthetic second failure.
      expect(errors, hasLength(1));
      expect(errors.single, isA<TransportFailure>());

      await client.dispose();
    },
  );

  test(
    'same-generation root-client replacement rebinds without reconnect loop',
    () async {
      final gateway = _ControlledGateway();
      final clientA = ArgusClient(gateway: gateway);

      final initializeA = clientA.initialize();
      await pumpEventQueue();
      gateway.startTask(0);
      await initializeA;
      await clientA.dispose();

      final clientB = ArgusClient(gateway: gateway);
      final errors = <Object>[];
      clientB.events.events.listen(null, onError: errors.add);
      final initializeB = clientB.initialize();
      await pumpEventQueue();
      gateway.startTask(1);
      await initializeB;

      // A fresh client reads the new admission epoch and its attach is
      // accepted; no reconnect loop or synthetic error occurs.
      expect(gateway.tasks[1].ended, isFalse);
      expect(errors, isEmpty);
      expect(
        gateway.tasks.where((task) => task.started && !task.ended),
        hasLength(1),
      );

      await clientB.dispose();
    },
  );

  test('dispose preserves ApplicationFailure from native close', () async {
    final gateway = _ControlledGateway()..closeFailure = _applicationFailure();
    final client = ArgusClient(gateway: gateway);

    final initialize = client.initialize();
    await pumpEventQueue();
    gateway.startTask(0);
    await initialize;

    await expectLater(client.dispose(), throwsA(isA<ApplicationFailure>()));
    expect(gateway.tasks[0].ended, isTrue);
  });

  test('dispose wraps unknown close exceptions as TransportFailure', () async {
    final gateway = _ControlledGateway()..closeFailure = StateError('boom');
    final client = ArgusClient(gateway: gateway);

    final initialize = client.initialize();
    await pumpEventQueue();
    gateway.startTask(0);
    await initialize;

    await expectLater(client.dispose(), throwsA(isA<TransportFailure>()));
    expect(gateway.tasks[0].ended, isTrue);
  });

  test(
    'primary shutdown failure wins over ApplicationFailure close failure',
    () async {
      final gateway = _ControlledGateway()
        ..failShutdown = true
        ..closeFailure = _applicationFailure();
      final client = ArgusClient(gateway: gateway);

      final initialize = client.initialize();
      await pumpEventQueue();
      gateway.startTask(0);
      await initialize;

      await expectLater(
        client.runtime.generalShutdown(),
        throwsA(isA<TransportFailure>()),
      );
      expect(gateway.tasks[0].ended, isTrue);
      expect(gateway.closeEventConnectionCalls, 1);

      await client.dispose();
    },
  );
}

final RuntimeInstanceId _idA = RuntimeInstanceId('a' * 32);

RuntimeState _failedA() => RuntimeState.startupFailed(
  runtimeInstanceId: _idA,
  failure: StartupFailure(
    phase: StartupPhase.settingsInitialization,
    error: ClientApplicationError(
      code: const ErrorCode(
        'ARGUS.V1.CONFIGURATION.PERSISTED_SETTINGS_INVALID',
      ),
      category: ErrorCategory.configuration,
      severity: ApplicationSeverity.error,
      recoverability: Recoverability.userAction,
      retryPolicy: RetryPolicy.userInitiated,
      messageKey: const MessageKey(
        'errors.configuration.persisted_settings_invalid',
      ),
      traceId: const TraceId('02020202020202020202020202020202'),
      safeContext: const <SafeContextEntry>[],
    ),
    recoveryActions: const <RecoveryAction>[
      RecoveryAction(kind: RecoveryActionKind.resetAppearanceSettings),
      RecoveryAction(kind: RecoveryActionKind.exit),
    ],
  ),
);

ApplicationFailure _applicationFailure() => ApplicationFailure(
  ClientApplicationError(
    code: const ErrorCode('ARGUS.V1.INTERNAL.UNEXPECTED'),
    category: ErrorCategory.internal,
    severity: ApplicationSeverity.error,
    recoverability: Recoverability.none,
    retryPolicy: RetryPolicy.never,
    messageKey: const MessageKey('errors.internal.unexpected'),
    traceId: const TraceId('03030303030303030303030303030303'),
    safeContext: const <SafeContextEntry>[],
  ),
);

final class _ControlledGateway
    with SourcesGatewayStub, JobsGatewayStub
    implements ArgusClientGateway {
  RuntimeState state = RuntimeState.ready(runtimeInstanceId: _idA);
  final List<_NativeTask> tasks = <_NativeTask>[];
  int generalShutdownCalls = 0;
  int closeEventConnectionCalls = 0;
  bool failShutdown = false;
  bool closeBoundaryOnShutdown = true;
  bool syncStreams = false;
  bool readEpochAtAttach = false;
  Object? closeFailure;
  int failCloseOnCall = 0;
  Object? lateCancelFailure;
  bool _boundaryClosed = false;
  int _admissionEpoch = 0;

  @override
  Future<RuntimeState> initialize() async => state;

  @override
  Future<RuntimeState> getRuntimeState() async => state;

  @override
  Future<RuntimeState> retryStartup(RuntimeInstanceId expected) async => state;

  @override
  Future<RuntimeState> resetAppearanceSettings(
    RuntimeInstanceId expected,
  ) async {
    // Emulates generation A retirement: the previous connection closes.
    for (final task in tasks) {
      task.close();
    }
    state = RuntimeState.ready(runtimeInstanceId: _idB());
    return state;
  }

  @override
  Future<RuntimeState> exitFailedRuntime(RuntimeInstanceId expected) async {
    for (final task in tasks) {
      task.close();
    }
    return RuntimeState.stopped(runtimeInstanceId: expected);
  }

  @override
  Future<void> generalShutdown() async {
    generalShutdownCalls++;
    if (failShutdown) {
      throw const TransportFailure('shutdown failed');
    }
    if (closeBoundaryOnShutdown) {
      _boundaryClosed = true;
    }
    for (final task in tasks.where((task) => task.started && !task.ended)) {
      task.close();
    }
  }

  @override
  Future<void> closeEventConnection() async {
    closeEventConnectionCalls++;
    // Production teardown advances the event-connection admission epoch so a
    // delayed attach from the retiring client is rejected while a fresh client
    // that re-reads the current epoch is still admitted to the same runtime
    // generation.
    _admissionEpoch++;
    for (final task in tasks.where((task) => task.started && !task.ended)) {
      task.close();
    }
    final failure = closeFailure;
    if (failure != null &&
        (failCloseOnCall == 0 ||
            closeEventConnectionCalls == failCloseOnCall)) {
      throw failure;
    }
  }

  @override
  Future<AppearanceSettings> getAppearanceSettings() async =>
      const AppearanceSettings(themeMode: ThemeMode.system);

  @override
  Future<void> updateAppearanceSettings(AppearanceSettings settings) async {}

  @override
  Future<DiagnosticsExport> exportStartupDiagnostics(
    RuntimeInstanceId expected,
    String destination,
  ) async => const DiagnosticsExport(
    outcome: DiagnosticsExportOutcome.created,
    destinationClassification: 'test',
  );

  @override
  Future<TechnicalDetails> startupTechnicalDetails(
    RuntimeInstanceId expected,
  ) async => const TechnicalDetails(text: 'details');

  @override
  Future<void> openStartupDataDirectory(RuntimeInstanceId expected) async {}

  @override
  Future<EventBindResult> subscribeEvents(RuntimeInstanceId generation) async {
    final task = _NativeTask(
      syncStreams,
      readEpochAtAttach ? null : _admissionEpoch,
      tasks.isEmpty ? null : lateCancelFailure,
    );
    tasks.add(task);
    await task.attach.future;
    return EventBindResult(stream: task.stream, nativeAttached: task.attached);
  }

  void startTask(int index) {
    tasks[index].start(
      boundaryClosed: _boundaryClosed,
      admissionEpoch: _admissionEpoch,
    );
  }
}

RuntimeInstanceId _idB() => RuntimeInstanceId('b' * 32);

final class _NativeTask {
  final Completer<void> _taskEnded = Completer<void>();
  StreamController<RuntimeEvent>? _controller;
  final bool _sync;
  final int? _epoch;
  final Object? _cancelFailure;
  final Completer<void> attach = Completer<void>();
  bool started = false;
  bool ended = false;
  bool attached = false;

  _NativeTask(this._sync, this._epoch, this._cancelFailure);

  Stream<RuntimeEvent> get stream {
    if (_sync) {
      _controller = StreamController<RuntimeEvent>.broadcast(sync: true);
      return _controller!.stream;
    }
    return Stream<RuntimeEvent>.multi((controller) {
      _controller = controller;
      controller.onCancel = () async {
        final failure = _cancelFailure;
        if (failure != null) throw failure;
        await _taskEnded.future;
      };
    });
  }

  void start({required bool boundaryClosed, required int admissionEpoch}) {
    started = true;
    final epoch = _epoch ?? admissionEpoch;
    if (boundaryClosed || epoch != admissionEpoch) {
      _end();
    } else {
      attached = true;
    }
    attach.complete();
  }

  void close() {
    if (ended) return;
    _end();
  }

  void addError(Object error) {
    _controller!.addError(error);
  }

  void _end() {
    if (ended) return;
    ended = true;
    _taskEnded.complete();
    _controller?.close();
  }
}
