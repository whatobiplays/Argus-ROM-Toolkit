import 'dart:async';

import 'package:argus/core/client/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'application/jobs_state.dart';

part 'jobs_composition.g.dart';

/// Focused Jobs capability injected by app composition.
@Riverpod(keepAlive: true)
JobsApi jobsApi(Ref ref) {
  throw StateError('jobsApiProvider must be supplied by app composition');
}

/// Runtime generation context injected by app composition.
@Riverpod(keepAlive: true)
JobsRuntimeContext jobsRuntimeContext(Ref ref) =>
    const JobsRuntimeContext.preReady();

/// Jobs reconciliation demand channel injected by app composition.
@Riverpod(keepAlive: true)
JobsReconciliationDemandSource jobsReconciliationDemand(Ref ref) =>
    const JobsReconciliationDemandSource(
      Stream<JobsReconciliationDemand>.empty(),
    );
