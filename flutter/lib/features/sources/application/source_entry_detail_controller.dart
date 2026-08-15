import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../sources_composition.dart';
import 'sources_state.dart';

part 'source_entry_detail_controller.g.dart';

/// Focused authoritative detail for one selected source entry.
///
/// The detail survives stable-ID moves even when the new hierarchy location is
/// not loaded, and it refreshes through a focused `getSourceEntry` read on any
/// source invalidation for the owning root (one bounded query, never an N+1
/// pattern).
@Riverpod(keepAlive: true)
class SourceEntryDetailController extends _$SourceEntryDetailController {
  @override
  Future<SourceEntryDetail> build({
    required LibraryRootId rootId,
    required SourceEntryId sourceEntryId,
  }) async {
    ref.watch(sourcesRuntimeContextProvider);
    final demandSource = ref.watch(sourcesReconciliationDemandProvider);
    late final StreamSubscription<SourcesReconciliationDemand> subscription;
    subscription = demandSource.stream.listen((demand) {
      if (demand is SourcesReconciliationDemandSourceChanged &&
          demand.libraryRootId == rootId) {
        ref.invalidateSelf();
      }
    });
    ref.onDispose(subscription.cancel);
    final api = ref.watch(sourcesApiProvider);
    return api.getSourceEntry(sourceEntryId);
  }
}
