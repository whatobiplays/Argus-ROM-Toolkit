import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'sources_state.freezed.dart';

/// Typed identity of the runtime generation that owns Sources authority.
///
/// The frontend never treats a submitted mutation or event payload as
/// authority; every confirmed value comes from a successful focused
/// authoritative read scoped to the current runtime.
@freezed
sealed class SourcesRuntimeContext with _$SourcesRuntimeContext {
  /// No usable runtime context has been published yet.
  const factory SourcesRuntimeContext.preReady() =
      SourcesRuntimeContextPreReady;

  /// A specific runtime generation is current and authoritative.
  const factory SourcesRuntimeContext.ready({
    required RuntimeInstanceId runtimeInstanceId,
  }) = SourcesRuntimeContextReady;
}

/// Narrow typed signal that Sources authority may have changed.
///
/// The signal carries bounded identity/invalidation information only; app
/// composition owns event interpretation and Sources controllers treat every
/// demand as "re-query authoritative Sources state".
@freezed
sealed class SourcesReconciliationDemand with _$SourcesReconciliationDemand {
  /// The configured root list or its authoritative ordering may have changed.
  const factory SourcesReconciliationDemand.rootsChanged() =
      SourcesReconciliationDemandRootsChanged;

  /// One root projection may have changed.
  const factory SourcesReconciliationDemand.rootChanged({
    required LibraryRootId libraryRootId,
  }) = SourcesReconciliationDemandRootChanged;

  /// One loaded source hierarchy scope may have changed.
  const factory SourcesReconciliationDemand.sourceChanged({
    required LibraryRootId libraryRootId,
    required SourceEntriesChangeScope scope,
  }) = SourcesReconciliationDemandSourceChanged;
}

/// Synchronous carrier for the Sources reconciliation demand stream.
///
/// This wrapper exists so the demand channel is an ordinary synchronous
/// Riverpod value instead of a generated Stream surface; the stream itself
/// remains privately owned by app composition.
final class SourcesReconciliationDemandSource {
  const SourcesReconciliationDemandSource(this.stream);

  final Stream<SourcesReconciliationDemand> stream;
}
