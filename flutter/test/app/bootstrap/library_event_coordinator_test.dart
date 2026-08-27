import 'dart:async';

import 'package:argus/app/bootstrap/library_event_coordinator.dart';
import 'package:argus/core/client/client.dart';
import 'package:argus/features/library/application/library_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _runtimeId = RuntimeInstanceId('1234567890abcdef1234567890abcdef');

RuntimeEvent _event(RuntimeEventPayload payload, BigInt sequence) =>
    RuntimeEvent(
      runtimeInstanceId: _runtimeId,
      sequence: sequence,
      occurredAtMs: BigInt.one,
      payload: payload,
    );

void main() {
  test(
    'a forward gap establishes a baseline without replaying the payload',
    () async {
      final events = StreamController<RuntimeEvent>.broadcast();
      final coordinator = LibraryEventCoordinator(
        events: _StreamEventsApi(events.stream),
        runtimeInstanceId: _runtimeId,
      );
      addTearDown(() async {
        coordinator.dispose();
        await events.close();
      });
      final demands = <LibraryReconciliationDemand>[];
      final subscription = coordinator.source.stream.listen(demands.add);
      addTearDown(subscription.cancel);

      events.add(
        _event(const RuntimeEventPayload.libraryRootsChanged(), BigInt.one),
      );
      await Future<void>.delayed(Duration.zero);
      events.add(
        _event(
          const RuntimeEventPayload.jobStateChanged(
            jobRunId: JobRunId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
          ),
          BigInt.from(3),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(demands, [
        const LibraryReconciliationDemand.listChanged(),
        const LibraryReconciliationDemand.listChanged(),
      ]);

      events.add(
        _event(const RuntimeEventPayload.libraryRootsChanged(), BigInt.from(4)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(demands, hasLength(3));
    },
  );
}

final class _StreamEventsApi implements EventsApi {
  _StreamEventsApi(this.stream);

  final Stream<RuntimeEvent> stream;

  @override
  Stream<RuntimeEvent> get events => stream;
}
