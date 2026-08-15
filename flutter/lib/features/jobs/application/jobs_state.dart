import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'jobs_state.freezed.dart';

/// Typed identity of the runtime generation that owns Jobs authority.
@freezed
sealed class JobsRuntimeContext with _$JobsRuntimeContext {
  /// No usable runtime context has been published yet.
  const factory JobsRuntimeContext.preReady() = JobsRuntimeContextPreReady;

  /// A specific runtime generation is current and authoritative.
  const factory JobsRuntimeContext.ready({
    required RuntimeInstanceId runtimeInstanceId,
  }) = JobsRuntimeContextReady;
}

/// Narrow typed signal that Jobs authority may have changed.
@freezed
sealed class JobsReconciliationDemand with _$JobsReconciliationDemand {
  /// The active/recent list or shell summary may have changed.
  const factory JobsReconciliationDemand.listChanged() =
      JobsReconciliationDemandListChanged;

  /// One job detail may have changed.
  const factory JobsReconciliationDemand.detailChanged({
    required JobRunId jobRunId,
  }) = JobsReconciliationDemandDetailChanged;
}

/// Synchronous carrier for the Jobs reconciliation demand stream.
final class JobsReconciliationDemandSource {
  const JobsReconciliationDemandSource(this.stream);

  final Stream<JobsReconciliationDemand> stream;
}
