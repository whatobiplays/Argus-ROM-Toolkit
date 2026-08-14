import 'dart:async';

import 'package:argus/app/bootstrap/appearance_event_coordinator.dart';
import 'package:argus/app/bootstrap/client_bootstrap.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/settings/application/appearance_settings_dependencies.dart';
import 'package:argus/features/settings/application/appearance_settings_state.dart';
import 'package:argus/features/startup/application/app_readiness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/startup/startup_test_fakes.dart';

/// Test-owned holder for the current ready runtime identity.
final class RuntimeIdentityHost extends Notifier<RuntimeInstanceId?> {
  @override
  RuntimeInstanceId? build() => null;

  void set(RuntimeInstanceId? value) => state = value;
}

final runtimeIdentityHostProvider =
    NotifierProvider<RuntimeIdentityHost, RuntimeInstanceId?>(
      RuntimeIdentityHost.new,
    );

/// Test-owned holder for the mapped EventsApi projection.
final class RuntimeEventsHost extends Notifier<EventsApi> {
  @override
  EventsApi build() => FakeEventsApi();

  void set(FakeEventsApi value) => state = value;
}

final runtimeEventsHostProvider =
    NotifierProvider<RuntimeEventsHost, EventsApi>(RuntimeEventsHost.new);

/// Widget harness mirroring the controller's production watch on the demand
/// seam. Watching keeps the coordinator's provider chain active so runtime
/// and EventsApi replacements propagate deterministically.
class _DemandHarness extends ConsumerStatefulWidget {
  const _DemandHarness({required this.onDemand});

  final void Function(AppearanceReconciliationDemand) onDemand;

  @override
  ConsumerState<_DemandHarness> createState() => _DemandHarnessState();
}

class _DemandHarnessState extends ConsumerState<_DemandHarness> {
  StreamSubscription<AppearanceReconciliationDemand>? _subscription;
  int _token = 0;

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(appearanceReconciliationDemandProvider);
    _token++;
    final token = _token;
    _subscription?.cancel();
    _subscription = source.stream.listen((demand) {
      if (token == _token) widget.onDemand(demand);
    });
    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    _token++;
    _subscription?.cancel();
    super.dispose();
  }
}

void main() {
  late ProviderContainer container;
  late FakeEventsApi events;
  final List<AppearanceReconciliationDemand> demandsSeen =
      <AppearanceReconciliationDemand>[];

  setUp(() {
    demandsSeen.clear();
    events = FakeEventsApi();
    container = ProviderContainer(
      overrides: [
        runtimeEventsProvider.overrideWith(
          (ref) => ref.watch(runtimeEventsHostProvider),
        ),
        readyRuntimeInstanceIdProvider.overrideWith(
          (ref) => ref.watch(runtimeIdentityHostProvider),
        ),
        appearanceReconciliationDemandProvider.overrideWith(
          (ref) => ref.watch(appearanceEventCoordinatorProvider),
        ),
      ],
    );
    container.read(runtimeEventsHostProvider.notifier).set(events);
    addTearDown(container.dispose);
  });

  Future<void> pumpHarness(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: _DemandHarness(onDemand: demandsSeen.add)),
      ),
    );
  }

  RuntimeIdentityHost identityHost() =>
      container.read(runtimeIdentityHostProvider.notifier);

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  RuntimeEvent event({
    required String runtime,
    required int sequence,
    RuntimeEventPayload payload = const RuntimeEventPayload.runtimeStateChanged(
      lifecycle: RuntimeLifecycle.ready,
    ),
  }) {
    return RuntimeEvent(
      runtimeInstanceId: testId(runtime),
      sequence: BigInt.from(sequence),
      occurredAtMs: BigInt.zero,
      payload: payload,
    );
  }

  RuntimeEvent appearanceEvent({
    required String runtime,
    required int sequence,
  }) {
    return event(
      runtime: runtime,
      sequence: sequence,
      payload: const RuntimeEventPayload.appearanceSettingsChanged(),
    );
  }

  group('sequence baseline and relevance', () {
    testWidgets(
      'first accepted current-generation event establishes the baseline '
      'without demand for an irrelevant payload',
      (tester) async {
        await pumpHarness(tester);
        identityHost().set(testId('a'));
        await settle(tester);

        events.emit(event(runtime: 'a', sequence: 7));
        await settle(tester);

        expect(demandsSeen, isEmpty);

        // Sequence 8 is contiguous with the established baseline 7.
        events.emit(appearanceEvent(runtime: 'a', sequence: 8));
        await settle(tester);

        expect(demandsSeen, hasLength(1));
      },
    );

    testWidgets(
      'contiguous appearance event requests one reconciliation demand',
      (tester) async {
        await pumpHarness(tester);
        identityHost().set(testId('a'));
        await settle(tester);

        events.emit(appearanceEvent(runtime: 'a', sequence: 1));
        await settle(tester);

        expect(demandsSeen, hasLength(1));
      },
    );

    testWidgets(
      'forward gap emits one demand even for an irrelevant payload and '
      'advances the baseline',
      (tester) async {
        await pumpHarness(tester);
        identityHost().set(testId('a'));
        await settle(tester);
        events.emit(event(runtime: 'a', sequence: 5));
        await settle(tester);

        events.emit(event(runtime: 'a', sequence: 8));
        await settle(tester);

        expect(demandsSeen, hasLength(1));

        // Baseline advanced to 8, so sequence 9 is contiguous.
        events.emit(event(runtime: 'a', sequence: 9));
        await settle(tester);

        expect(demandsSeen, hasLength(1));
      },
    );

    testWidgets(
      'duplicate and regressive sequences each emit one demand but never '
      'rewind the baseline',
      (tester) async {
        await pumpHarness(tester);
        identityHost().set(testId('a'));
        await settle(tester);
        events.emit(event(runtime: 'a', sequence: 5));
        await settle(tester);

        events.emit(event(runtime: 'a', sequence: 5));
        await settle(tester);
        events.emit(event(runtime: 'a', sequence: 4));
        await settle(tester);

        expect(demandsSeen, hasLength(2));

        // Baseline is still 5, so sequence 6 is contiguous.
        events.emit(appearanceEvent(runtime: 'a', sequence: 6));
        await settle(tester);

        expect(demandsSeen, hasLength(3));
      },
    );

    testWidgets(
      'appearance event with a sequence discontinuity produces exactly one '
      'demand',
      (tester) async {
        await pumpHarness(tester);
        identityHost().set(testId('a'));
        await settle(tester);
        events.emit(event(runtime: 'a', sequence: 5));
        await settle(tester);

        events.emit(appearanceEvent(runtime: 'a', sequence: 8));
        await settle(tester);

        expect(demandsSeen, hasLength(1));
      },
    );

    testWidgets('contiguous runtime/startup payloads never request a read', (
      tester,
    ) async {
      await pumpHarness(tester);
      identityHost().set(testId('a'));
      await settle(tester);

      events.emit(event(runtime: 'a', sequence: 1));
      await settle(tester);
      events.emit(event(runtime: 'a', sequence: 2));
      await settle(tester);
      events.emit(
        event(
          runtime: 'a',
          sequence: 3,
          payload: const RuntimeEventPayload.startupFailed(
            phase: StartupPhase.readinessValidation,
          ),
        ),
      );
      await settle(tester);

      expect(demandsSeen, isEmpty);
    });
  });

  group('stream uncertainty', () {
    testWidgets(
      'mapped stream error requests reconciliation for the ready runtime',
      (tester) async {
        await pumpHarness(tester);
        identityHost().set(testId('a'));
        await settle(tester);

        events.emitError(
          const TransportFailure(
            'native event stream interrupted',
            kind: TransportFailureKind.communicationFailed,
          ),
        );
        await settle(tester);

        expect(demandsSeen, hasLength(1));
      },
    );

    testWidgets('mapped stream completion requests reconciliation when ready', (
      tester,
    ) async {
      await pumpHarness(tester);
      identityHost().set(testId('a'));
      await settle(tester);

      await events.close();
      await settle(tester);

      expect(demandsSeen, hasLength(1));
    });

    testWidgets('pre-ready stream error and completion emit no demand', (
      tester,
    ) async {
      await pumpHarness(tester);

      events.emitError(const TransportFailure('interrupted'));
      await settle(tester);
      await events.close();
      await settle(tester);

      expect(demandsSeen, isEmpty);
    });
  });

  group('runtime and provider replacement', () {
    testWidgets(
      'ready-runtime replacement resets the sequence domain and stale events '
      'never emit demand or mutate the baseline',
      (tester) async {
        await pumpHarness(tester);
        identityHost().set(testId('a'));
        await settle(tester);
        events.emit(event(runtime: 'a', sequence: 5));
        await settle(tester);

        identityHost().set(testId('b'));
        await settle(tester);

        // Runtime A event after B is current: ignored.
        events.emit(appearanceEvent(runtime: 'a', sequence: 6));
        await settle(tester);
        expect(demandsSeen, isEmpty);

        // First B event establishes B's baseline.
        events.emit(event(runtime: 'b', sequence: 1));
        await settle(tester);
        expect(demandsSeen, isEmpty);

        // Contiguous B appearance event is relevant.
        events.emit(appearanceEvent(runtime: 'b', sequence: 2));
        await settle(tester);
        expect(demandsSeen, hasLength(1));
      },
    );

    testWidgets(
      'EventsApi replacement resubscribes, resets tracking, and suppresses '
      'old-stream completion signals',
      (tester) async {
        await pumpHarness(tester);
        identityHost().set(testId('a'));
        await settle(tester);
        events.emit(event(runtime: 'a', sequence: 5));
        await settle(tester);
        expect(events.activeListens, 1);

        final replacement = FakeEventsApi();
        container.read(runtimeEventsHostProvider.notifier).set(replacement);
        await settle(tester);
        expect(replacement.activeListens, 1);
        expect(events.activeListens, 0);

        // Closing the retired stream must not publish into the new domain.
        await events.close();
        await settle(tester);
        expect(demandsSeen, isEmpty);

        replacement.emit(event(runtime: 'a', sequence: 3));
        await settle(tester);
        replacement.emit(appearanceEvent(runtime: 'a', sequence: 4));
        await settle(tester);

        expect(demandsSeen, hasLength(1));
      },
    );

    testWidgets('pre-ready events are ignored entirely', (tester) async {
      await pumpHarness(tester);
      events.emit(appearanceEvent(runtime: 'a', sequence: 1));
      await settle(tester);

      expect(demandsSeen, isEmpty);

      // Runtime A event emitted before readiness does not become the baseline
      // for the later ready domain.
      identityHost().set(testId('a'));
      await settle(tester);
      events.emit(appearanceEvent(runtime: 'a', sequence: 2));
      await settle(tester);

      expect(demandsSeen, hasLength(1));
    });
  });
}
